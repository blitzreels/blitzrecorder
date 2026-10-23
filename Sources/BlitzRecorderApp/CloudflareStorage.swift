import Foundation
import Security

/// Video storage in the user's own Cloudflare account: an R2 bucket behind a small media worker we deploy for them.
struct CloudflareStorageConnection: Codable, Equatable, Sendable {
    let accountID: String
    let accountName: String
    let mediaOrigin: URL
    let uploadSecret: String
    let apiToken: String

    var displayHost: String { mediaOrigin.host ?? mediaOrigin.absoluteString }
}

struct KeychainItem {
    let account: String

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "dev.blitzreels.blitzrecorder",
         kSecAttrAccount as String: account]
    }

    func load() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func clear() { SecItemDelete(query as CFDictionary) }

    func save(_ data: Data) -> Bool {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

struct CloudflareStorageStore {
    private let item = KeychainItem(account: "cloudflare-storage")

    func load() -> CloudflareStorageConnection? {
        item.load().flatMap { try? JSONDecoder().decode(CloudflareStorageConnection.self, from: $0) }
    }

    func save(_ connection: CloudflareStorageConnection) throws {
        guard let data = try? JSONEncoder().encode(connection), item.save(data) else {
            throw HostingFailure(message: "Your Cloudflare connection could not be saved in Keychain.")
        }
    }

    func clear() { item.clear() }
}

enum CloudflareSetupStep: Int, CaseIterable, Sendable {
    case checkingToken, creatingStorage, installingPlayer, goingLive

    var title: String {
        switch self {
        case .checkingToken: "Checking your token"
        case .creatingStorage: "Creating your video storage"
        case .installingPlayer: "Installing the video player"
        case .goingLive: "Bringing your player online"
        }
    }
}

/// A setup failure the user can fix in the Cloudflare dashboard.
struct CloudflareSetupFailure: LocalizedError {
    let message: String
    let fixURL: URL?
    let fixTitle: String?
    var errorDescription: String? { message }
}

struct CloudflareSetup {
    static let scriptName = "blitzrecorder-media"
    static let bucketName = "blitzrecorder-videos"
    /// Opens Cloudflare's token form with exactly the permissions setup needs.
    static let tokenTemplateURL: URL = {
        let permissions = #"[{"key":"workers_scripts","type":"edit"},{"key":"workers_r2","type":"edit"},{"key":"account_settings","type":"read"}]"#
        var components = URLComponents(string: "https://dash.cloudflare.com/profile/api-tokens")!
        components.queryItems = [
            .init(name: "permissionGroupKeys", value: permissions), .init(name: "accountId", value: "*"),
            .init(name: "zoneId", value: "all"), .init(name: "name", value: "BlitzRecorder video storage"),
        ]
        return components.url!
    }()
    static let enableR2URL = URL(string: "https://dash.cloudflare.com/?to=/:account/r2/overview")!

    let session: URLSession

    static var configured: Self {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        return .init(session: URLSession(configuration: config, delegate: HostingRedirectPolicy(), delegateQueue: nil))
    }

    struct Request {
        let token: String
        let progress: @MainActor (CloudflareSetupStep) -> Void
    }

    func connect(_ request: Request) async throws -> CloudflareStorageConnection {
        let api = CloudflareAPI(token: request.token, session: session)
        await request.progress(.checkingToken)
        struct Account: Decodable { let id: String; let name: String }
        let accounts: [Account] = try await api.call(.init(method: "GET", path: "accounts?per_page=50", body: nil))
        guard let account = accounts.first, account.id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else {
            throw CloudflareSetupFailure(message: "This token can’t see a Cloudflare account. Create it again and keep “All accounts” selected.",
                fixURL: Self.tokenTemplateURL, fixTitle: "Create token")
        }
        let accountPath = "accounts/\(account.id)"

        await request.progress(.creatingStorage)
        do {
            struct Bucket: Decodable { let name: String }
            let _: Bucket = try await api.call(.init(method: "POST", path: "\(accountPath)/r2/buckets",
                body: .json(["name": Self.bucketName])))
        } catch let failure as CloudflareAPI.Failure where failure.codes.contains(10004) {
        } catch let failure as CloudflareAPI.Failure where failure.codes.contains(10042) {
            throw CloudflareSetupFailure(message: "R2 storage isn’t turned on in your Cloudflare account yet. Turn it on (the free plan is enough), then connect again.",
                fixURL: Self.enableR2URL, fixTitle: "Turn on R2")
        }

        await request.progress(.installingPlayer)
        let secret = Self.randomSecret()
        try await installWorker(.init(api: api, accountPath: accountPath, secret: secret))
        let subdomain = try await accountSubdomain(api: api, accountPath: accountPath)
        struct Enabled: Decodable { let enabled: Bool? }
        let _: Enabled = try await api.call(.init(method: "POST", path: "\(accountPath)/workers/scripts/\(Self.scriptName)/subdomain",
            body: .json(["enabled": true, "previews_enabled": false])))

        await request.progress(.goingLive)
        guard let origin = URL(string: "https://\(Self.scriptName).\(subdomain).workers.dev") else {
            throw HostingFailure(message: "Cloudflare returned an invalid workers.dev address.")
        }
        let connection = CloudflareStorageConnection(accountID: account.id, accountName: account.name, mediaOrigin: origin,
                                                     uploadSecret: secret, apiToken: request.token)
        try await waitUntilLive(connection)
        return connection
    }

    /// The worker version this app ships (`VERSION` in `CloudflareMediaWorker.mjs`).
    static let workerVersion = 2

    private struct WorkerInstall {
        let api: CloudflareAPI
        let accountPath: String
        let secret: String
    }

    private func installWorker(_ install: WorkerInstall) async throws {
        guard let scriptURL = Bundle.main.url(forResource: "CloudflareMediaWorker", withExtension: "mjs"),
              let script = try? Data(contentsOf: scriptURL) else {
            throw HostingFailure(message: "BlitzRecorder is missing its video player. Reinstall the app and try again.")
        }
        let metadata: [String: Any] = [
            "main_module": "worker.mjs", "compatibility_date": "2026-10-01",
            "bindings": [
                ["type": "r2_bucket", "name": "MEDIA", "bucket_name": Self.bucketName],
                ["type": "secret_text", "name": "UPLOAD_SECRET", "text": install.secret],
            ],
        ]
        struct Script: Decodable { let id: String? }
        let _: Script = try await install.api.call(.init(method: "PUT",
            path: "\(install.accountPath)/workers/scripts/\(Self.scriptName)",
            body: .multipart([
                .init(name: "metadata", filename: nil, contentType: "application/json",
                      data: try JSONSerialization.data(withJSONObject: metadata)),
                .init(name: "worker.mjs", filename: "worker.mjs", contentType: "application/javascript+module", data: script),
            ])))
    }

    /// Workers installed by an older app keep running their old code; this replaces one older than the app's,
    /// with the same upload secret, so existing links and uploads keep working.
    func upgradeWorkerIfNeeded(_ connection: CloudflareStorageConnection) async throws {
        struct Health: Decodable { let version: Int? }
        let (data, _) = try await session.data(from: connection.mediaOrigin.appendingPathComponent("health"))
        let installed = (try? JSONDecoder().decode(Health.self, from: data))?.version ?? 0
        guard installed < Self.workerVersion else { return }
        try await installWorker(.init(api: CloudflareAPI(token: connection.apiToken, session: session),
            accountPath: "accounts/\(connection.accountID)", secret: connection.uploadSecret))
    }

    func disconnect(_ connection: CloudflareStorageConnection) async {
        let api = CloudflareAPI(token: connection.apiToken, session: session)
        struct Enabled: Decodable { let enabled: Bool? }
        let _: Enabled? = try? await api.call(.init(method: "POST",
            path: "accounts/\(connection.accountID)/workers/scripts/\(Self.scriptName)/subdomain",
            body: .json(["enabled": false, "previews_enabled": false])))
    }

    private func accountSubdomain(api: CloudflareAPI, accountPath: String) async throws -> String {
        struct Subdomain: Decodable { let subdomain: String }
        let valid = "^[a-z0-9-]{1,63}$"
        if let existing: Subdomain = try? await api.call(.init(method: "GET", path: "\(accountPath)/workers/subdomain", body: nil)),
           existing.subdomain.range(of: valid, options: .regularExpression) != nil {
            return existing.subdomain
        }
        let name = "blitz-" + String(UUID().uuidString.lowercased().prefix(8))
        let created: Subdomain = try await api.call(.init(method: "PUT", path: "\(accountPath)/workers/subdomain",
            body: .json(["subdomain": name])))
        guard created.subdomain.range(of: valid, options: .regularExpression) != nil else {
            throw HostingFailure(message: "Cloudflare returned an invalid workers.dev address.")
        }
        return created.subdomain
    }

    /// A brand-new workers.dev address can take a minute to resolve.
    private func waitUntilLive(_ connection: CloudflareStorageConnection) async throws {
        struct Health: Decodable { let blitzrecorder: Bool; let upload: Bool }
        var request = URLRequest(url: connection.mediaOrigin.appendingPathComponent("health"))
        request.setValue("Bearer \(connection.uploadSecret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let deadline = ContinuousClock.now.advanced(by: .seconds(150))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let (data, response) = try? await session.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let health = try? JSONDecoder().decode(Health.self, from: data), health.blitzrecorder, health.upload {
                return
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw HostingFailure(message: "Your player is installed but Cloudflare hasn’t put it online yet. Wait a minute, then connect again.")
    }

    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct CloudflareAPI {
    static let base = URL(string: "https://api.cloudflare.com/client/v4/")!
    let token: String
    let session: URLSession

    struct Part {
        let name: String
        let filename: String?
        let contentType: String
        let data: Data
    }
    enum Body {
        case json([String: Any])
        case multipart([Part])
    }
    struct Call {
        let method: String
        let path: String
        let body: Body?
    }
    struct Failure: LocalizedError {
        let codes: [Int]
        let message: String
        var errorDescription: String? { message }
    }
    private struct Envelope<T: Decodable>: Decodable {
        struct Message: Decodable { let code: Int; let message: String }
        let success: Bool
        let errors: [Message]?
        let result: T?
    }

    func call<T: Decodable>(_ call: Call) async throws -> T {
        guard let url = URL(string: call.path, relativeTo: Self.base) else { throw HostingFailure(message: "Invalid Cloudflare request.") }
        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        switch call.body {
        case .json(let value):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: value)
        case .multipart(let parts):
            let boundary = "blitzrecorder-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            for part in parts {
                let filename = part.filename.map { "; filename=\"\($0)\"" } ?? ""
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part.name)\"\(filename)\r\nContent-Type: \(part.contentType)\r\n\r\n".utf8))
                body.append(part.data)
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            request.httpBody = body
        case nil:
            break
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw HostingFailure(message: "Couldn’t reach Cloudflare. Check your connection and try again.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data)
        if let envelope, envelope.success, let result = envelope.result { return result }
        let codes = envelope?.errors?.map(\.code) ?? []
        if status == 401 || status == 403 || codes.contains(10000) || codes.contains(9109) {
            throw CloudflareSetupFailure(message: "Cloudflare didn’t accept this token. Create one with the button above so it has the right permissions.",
                fixURL: CloudflareSetup.tokenTemplateURL, fixTitle: "Create token")
        }
        throw Failure(codes: codes, message: envelope?.errors?.first.map { "Cloudflare: \($0.message)" }
            ?? "Cloudflare couldn’t finish setup. Try again.")
    }
}

/// Talks to the media worker in the user's account. Every call carries the upload secret set during setup.
struct CloudflareMediaClient: Sendable {
    let connection: CloudflareStorageConnection
    let session: URLSession

    struct UploadedPart: Codable, Sendable {
        let part: Int
        let etag: String
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: connection.mediaOrigin.absoluteString + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(connection.uploadSecret)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, body: Data?) async throws -> T {
        var request = request
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw HostingFailure(message: "Your Cloudflare storage needs to be reconnected. Open Share and connect it again.") }
        guard (200..<300).contains(status) else { throw HostingFailure(message: "Your Cloudflare storage stopped the upload. Resume to try again.") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? value
    }

    func createUpload(assetID: String) async throws -> String {
        struct Created: Decodable { let uploadId: String }
        let created: Created = try await send(request("/u/\(assetID)/video.mp4?uploads", method: "POST"), body: nil)
        return created.uploadId
    }

    func partRequest(assetID: String, uploadID: String, number: Int) -> URLRequest {
        let upload = Self.escaped(uploadID)
        return request("/u/\(assetID)/video.mp4?uploadId=\(upload)&part=\(number)", method: "PUT")
    }

    func complete(assetID: String, uploadID: String, parts: [UploadedPart]) async throws {
        struct Completed: Decodable { let bytes: Int }
        let upload = Self.escaped(uploadID)
        var call = request("/u/\(assetID)/video.mp4?uploadId=\(upload)", method: "POST")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let _: Completed = try await send(call, body: JSONEncoder().encode(["parts": parts.sorted { $0.part < $1.part }]))
    }

    func delete(assetID: String) async throws {
        struct Deleted: Decodable { let deleted: Bool }
        let _: Deleted = try await send(request("/u/\(assetID)", method: "DELETE"), body: nil)
    }

    func putPoster(assetID: String, jpeg: Data) async throws {
        struct Saved: Decodable { let saved: Bool }
        var call = request("/u/\(assetID)/poster.jpg", method: "PUT")
        call.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let _: Saved = try await send(call, body: jpeg)
    }

    struct PreviewFile {
        let assetID: String
        let mp4: Data
    }

    func putPreview(_ file: PreviewFile) async throws {
        struct Saved: Decodable { let saved: Bool }
        var call = request("/u/\(file.assetID)/preview.mp4", method: "PUT")
        call.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        let _: Saved = try await send(call, body: file.mp4)
    }
}

/// Remembers finished parts so a paused upload to the user's bucket resumes instead of starting over.
actor CloudflareUploadJournal {
    private struct Entry: Codable {
        let uploadID: String
        var parts: [Int: String]
    }
    private let key: String
    private var entry: Entry?

    init(assetID: String) {
        key = "CloudflareUpload:\(assetID)"
        entry = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Entry.self, from: $0) }
    }

    var uploadID: String? { entry?.uploadID }
    var parts: [CloudflareMediaClient.UploadedPart] {
        (entry?.parts ?? [:]).map { .init(part: $0.key, etag: $0.value) }
    }

    func start(uploadID: String) {
        entry = Entry(uploadID: uploadID, parts: [:])
        persist()
    }

    func record(_ part: CloudflareMediaClient.UploadedPart) {
        entry?.parts[part.part] = part.etag
        persist()
    }

    func clear() {
        entry = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func persist() {
        if let entry, let data = try? JSONEncoder().encode(entry) { UserDefaults.standard.set(data, forKey: key) }
    }
}
