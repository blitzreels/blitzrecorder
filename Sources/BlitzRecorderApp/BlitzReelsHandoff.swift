import AppKit
import Observation
import Security

struct BlitzReelsHTTPRequest {
    let path: String
    let method: String
    let key: String?
    let body: [String: Any]?
}

struct BlitzReelsHTTPClient {
    let origin: URL
    let session: URLSession

    func send<Response: Decodable>(_ request: BlitzReelsHTTPRequest) async throws -> Response {
        var http = URLRequest(url: origin.appendingPathComponent(request.path))
        http.httpMethod = request.method
        http.timeoutInterval = 60
        if let key = request.key { http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body = request.body {
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
            http.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: http)
        try Self.validate(.init(data: data, response: response))
        return try JSONDecoder().decode(Response.self, from: data)
    }

    struct ResponseValidation { let data: Data; let response: URLResponse }
    static func validate(_ request: ResponseValidation) throws {
        guard let response = request.response as? HTTPURLResponse else { throw BlitzReelsHandoffError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw BlitzReelsHandoffError.signInAgain }
            if response.statusCode == 403 { throw BlitzReelsHandoffError.planAccess }
            if response.statusCode == 429 { throw BlitzReelsHandoffError.rateLimited }
            throw BlitzReelsHandoffError.server(response.statusCode)
        }
    }

    struct CreateURLRequest { let assetID: String; let organizationID: String }
    func createURL(_ request: CreateURLRequest) -> URL {
        var parts = URLComponents(url: origin.appendingPathComponent("dashboard/create"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "mode", value: "clips"), .init(name: "source", value: "blitzrecorder"),
                            .init(name: "asset", value: request.assetID), .init(name: "org", value: request.organizationID)]
        return parts.url!
    }
}

struct BlitzReelsAPIKeyStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "dev.blitzreels.blitzrecorder",
         kSecAttrAccount as String: "blitzreels-media-api-key"]
    }
    func load() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw BlitzReelsHandoffError.keychain }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BlitzReelsHandoffError.keychain }
    }
    func clear() { SecItemDelete(query as CFDictionary) }
}

struct BlitzReelsDeviceAuthorization: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri_complete: URL
    let expires_in: Int
    let interval: Int
}
struct BlitzReelsDeviceToken: Decodable { let status: String; let api_key: String? }
struct BlitzReelsAccount: Decodable { let organization_id: String; let key_prefix: String; let plan: String }
struct BlitzReelsUploadInit: Decodable { let upload_url: URL; let storage_key: String }
struct BlitzReelsUploadResult: Decodable { let id: String; let processing_status: String }
struct BlitzReelsHandoffRecord: Codable {
    let filePath: String
    let fileSize: Int64
    let modifiedAt: Date
    let assetID: String
    let organizationID: String
    let createdAt: Date
}
struct BlitzReelsSendRequest {
    let fileURL: URL
    let project: RecordingProject
    let settings: RecordingSettings
}

@MainActor
@Observable
final class BlitzReelsHandoffController {
    static let shared = BlitzReelsHandoffController()
    private(set) var projectID: UUID?
    private(set) var status = "Send a recording to your BlitzReels workspace."
    private(set) var userCode: String?
    private(set) var isWorking = false
    private(set) var progress: Double?
    private(set) var createURL: URL?
    private(set) var account: BlitzReelsAccount?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let client = BlitzReelsHTTPClient(origin: URL(string: "https://blitzreels.com")!, session: .shared)
    @ObservationIgnored private let keyStore = BlitzReelsAPIKeyStore()

    var hasKey: Bool { keyStore.load() != nil }

    func cancel() { task?.cancel() }
    func disconnect() {
        task?.cancel()
        keyStore.clear()
        account = nil
        status = "Disconnected on this Mac. Revoke the key in BlitzReels API settings to remove server access."
    }

    func send(_ request: BlitzReelsSendRequest) {
        guard !isWorking else { return }
        isWorking = true
        projectID = request.project.id
        createURL = nil
        progress = nil
        task = Task {
            defer { isWorking = false; userCode = nil; progress = nil; task = nil }
            do {
                let access = try TakeFileStore().prepareOutputDirectory(settings: request.settings)
                defer { access.stop() }
                let scoped = request.fileURL.startAccessingSecurityScopedResource()
                defer { if scoped { request.fileURL.stopAccessingSecurityScopedResource() } }
                guard FileManager.default.isReadableFile(atPath: request.fileURL.path) else { throw BlitzReelsHandoffError.fileAccess }
                let values = try request.fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values.fileSize ?? 0)
                guard size > 0 && size <= 5 * 1024 * 1024 * 1024 else { throw BlitzReelsHandoffError.fileSize }
                guard let modified = values.contentModificationDate else { throw BlitzReelsHandoffError.fileAccess }
                let key = try await connect()
                let account: BlitzReelsAccount = try await client.send(.init(path: "api/v1/auth/validate", method: "GET", key: key, body: nil))
                self.account = account
                let sidecar = URL(fileURLWithPath: request.project.takeDirectoryPath).appendingPathComponent("blitzreels-handoff.json")
                if let data = try? Data(contentsOf: sidecar),
                   let saved = try? JSONDecoder().decode(BlitzReelsHandoffRecord.self, from: data),
                   saved.filePath == request.fileURL.path, saved.fileSize == size, saved.modifiedAt == modified,
                   saved.organizationID == account.organization_id {
                    finish(.init(assetID: saved.assetID, organizationID: saved.organizationID))
                    return
                }
                status = "Preparing video and audio…"
                let prepared = try await RecordingUploadSource.prepare(.init(fileURL: request.fileURL, project: request.project))
                defer { if prepared.temporary { try? FileManager.default.removeItem(at: prepared.url) } }
                let uploadSize = Int64(try prepared.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                guard uploadSize > 0 && uploadSize <= 5 * 1024 * 1024 * 1024 else { throw BlitzReelsHandoffError.fileSize }
                status = "Preparing upload…"
                let contentType = prepared.url.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
                let name = String(request.fileURL.deletingPathExtension().lastPathComponent.prefix(190)) + "." + prepared.url.pathExtension
                let upload: BlitzReelsUploadInit = try await client.send(.init(path: "api/v1/workspace/media/upload/init", method: "POST", key: key,
                    body: ["file_name": name, "content_type": contentType, "file_size_bytes": uploadSize]))
                guard upload.upload_url.scheme == "https" else { throw BlitzReelsHandoffError.invalidResponse }
                status = "Uploading \(name)…"
                var put = URLRequest(url: upload.upload_url)
                put.httpMethod = "PUT"
                put.timeoutInterval = 3600
                put.setValue(contentType, forHTTPHeaderField: "Content-Type")
                let delegate = BlitzReelsUploadProgress { [weak self] fraction in
                    Task { @MainActor in self?.progress = fraction }
                }
                let (data, response) = try await client.session.upload(for: put, fromFile: prepared.url, delegate: delegate)
                try BlitzReelsHTTPClient.validate(.init(data: data, response: response))
                try Task.checkCancellation()
                status = "Saving in BlitzReels…"
                let result: BlitzReelsUploadResult = try await client.send(.init(path: "api/v1/workspace/media/upload/finalize", method: "POST", key: key,
                    body: ["storage_key": upload.storage_key, "file_name": name, "content_type": contentType, "file_size_bytes": uploadSize,
                           "auto_process_enabled": true, "auto_transcribe": false, "auto_describe_after_transcribe": false, "auto_suggest_shorts": false]))
                try Task.checkCancellation()
                let record = BlitzReelsHandoffRecord(filePath: request.fileURL.path, fileSize: size, modifiedAt: modified,
                    assetID: result.id, organizationID: account.organization_id, createdAt: Date())
                if FileManager.default.fileExists(atPath: request.project.takeDirectoryPath) {
                    try? JSONEncoder().encode(record).write(to: sidecar, options: .atomic)
                }
                finish(.init(assetID: result.id, organizationID: account.organization_id))
            } catch is CancellationError { status = "Upload cancelled. Your recording is still on this Mac." }
            catch {
                if case BlitzReelsHandoffError.signInAgain = error { keyStore.clear(); account = nil }
                status = error.localizedDescription
            }
        }
    }

    private func connect() async throws -> String {
        if let key = keyStore.load() { return key }
        status = "Connect in your browser, then return here."
        let authorization: BlitzReelsDeviceAuthorization = try await client.send(.init(path: "api/cli/auth/device", method: "POST", key: nil, body: [:]))
        guard authorization.verification_uri_complete.scheme == "https",
              authorization.verification_uri_complete.host == client.origin.host else { throw BlitzReelsHandoffError.invalidResponse }
        userCode = authorization.user_code
        NSWorkspace.shared.open(authorization.verification_uri_complete)
        let deadline = Date().addingTimeInterval(Double(authorization.expires_in))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(max(1, authorization.interval)))
            let token: BlitzReelsDeviceToken = try await client.send(.init(path: "api/cli/auth/token", method: "POST", key: nil,
                body: ["device_code": authorization.device_code]))
            if token.status == "approved", let key = token.api_key {
                try keyStore.save(key)
                userCode = nil
                return key
            }
            if ["denied", "expired", "invalid", "consumed"].contains(token.status) { throw BlitzReelsHandoffError.authorizationExpired }
        }
        throw BlitzReelsHandoffError.authorizationExpired
    }

    private func finish(_ request: BlitzReelsHTTPClient.CreateURLRequest) {
        let url = client.createURL(request)
        createURL = url
        status = "Uploaded. Choose your clips in BlitzReels."
        NSWorkspace.shared.open(url)
    }
}

private final class BlitzReelsUploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        update(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

enum BlitzReelsHandoffError: LocalizedError {
    case invalidResponse, signInAgain, planAccess, rateLimited, keychain, fileAccess, fileSize, authorizationExpired
    case server(Int)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "BlitzReels returned an unexpected response. Try again."
        case .signInAgain: "Your BlitzReels connection expired. Send again to reconnect."
        case .planAccess: "Your BlitzReels workspace cannot accept this upload. Check its plan and storage allowance."
        case .rateLimited: "BlitzReels is busy. Try again in a moment."
        case .keychain: "The connection could not be saved securely in Keychain."
        case .fileAccess: "This file is no longer accessible. Export it again to a folder BlitzRecorder can access."
        case .fileSize: "Choose a non-empty recording up to 5 GB. Export a smaller version for larger takes."
        case .authorizationExpired: "Connection was declined or expired. Send again to reconnect."
        case .server(let status): "BlitzReels could not finish the request (\(status)). Try again."
        }
    }
}
