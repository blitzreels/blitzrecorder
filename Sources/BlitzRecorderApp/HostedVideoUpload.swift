import AVFoundation
import Foundation
import Security

struct HostingFailure: LocalizedError {
    let message: String
    var status: Int? = nil
    var errorDescription: String? { message }
}

struct HostingPlan: Decodable {
    let name: String
    let amount: Int
    let currency: String
    let storageBytes: Int64
    let uploadSeconds: Int
    let uploadWindowDays: Int
    let maximumResolution: Int
    let retentionDaysAfterExpiry: Int
    let available: Bool

    var price: String {
        (Double(amount) / 100).formatted(.currency(code: currency.uppercased()).precision(.fractionLength(0)))
    }

    var allowance: String {
        "\(storageBytes / 1_000_000_000) GB storage · \(uploadSeconds / 3600) hours uploaded per \(uploadWindowDays) days"
    }
}

struct HostingAsset: Decodable {
    struct Part: Decodable { let number: Int; let bytes: Int }
    let id: String
    let status: String
    let sharePath: String?
    let error: String?
    var partBytes: Int? = nil
    var parts: Int? = nil
    var uploadedParts: [Part]? = nil
}

final class HostingRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct HostingClient {
    let origin: URL
    let session: URLSession

    static var configured: Self {
        var origin = URL(string: "https://blitzrecorder.com")!
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "HostingOrigin"), let local = URL(string: value),
           ["localhost", "127.0.0.1"].contains(local.host ?? ""), ["http", "https"].contains(local.scheme ?? "") {
            origin = local
        }
        #endif
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return .init(origin: origin, session: URLSession(configuration: config, delegate: HostingRedirectPolicy(), delegateQueue: nil))
    }

    struct Request {
        let route: String
        let token: String?
        let body: Data?
    }

    private struct Failure: Decodable { let error: String }

    func send<T: Decodable>(_ request: Request) async throws -> T {
        let url = origin.appendingPathComponent("api/hosting").appendingPathComponent(request.route)
        var http = URLRequest(url: url)
        http.httpMethod = request.body == nil ? "GET" : "POST"
        http.httpBody = request.body
        if let token = request.token { http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: http)
        guard let response = response as? HTTPURLResponse else { throw HostingFailure(message: "The hosting service did not respond.") }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "Sharing was interrupted. Try again."
            throw HostingFailure(message: message, status: response.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func shareURL(_ path: String) throws -> URL {
        guard path.range(of: "^/s/[A-Za-z0-9_-]{24}$", options: .regularExpression) != nil else {
            throw HostingFailure(message: "The sharing link is invalid.")
        }
        return origin.appendingPathComponent(String(path.dropFirst()))
    }

    struct Upload {
        let fileURL: URL
        let token: String
        let metadata: HostingExportMetadata
        let progress: @Sendable (Progress) async -> Void
    }
    enum Progress: Sendable {
        case uploading(Double)
        case processing
    }

    func upload(_ request: Upload) async throws -> URL {
        let values = try request.fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let bytes = values.fileSize, bytes >= 16, bytes <= 5 * 1024 * 1024 * 1024,
              ["mp4", "mov"].contains(request.fileURL.pathExtension.lowercased()) else {
            throw HostingFailure(message: "Choose an exported MP4 or MOV smaller than 5 GB.")
        }
        let duration = try await AVURLAsset(url: request.fileURL).load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 3600 else {
            throw HostingFailure(message: "Sharing supports videos up to one hour long.")
        }
        let key = try HostingExportMetadata.fingerprint(request.fileURL)
        let body: [String: Any] = ["title": String(request.metadata.title.prefix(160)), "bytes": bytes,
            "duration": duration, "contentType": request.fileURL.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4",
            "requestKey": key]
        let asset: HostingAsset = try await send(.init(route: "assets", token: request.token,
            body: JSONSerialization.data(withJSONObject: body)))
        guard UUID(uuidString: asset.id) != nil else { throw HostingFailure(message: "The upload could not be created.") }
        if asset.status == "ready", let path = asset.sharePath { return try shareURL(path) }
        if ["failed", "revoked"].contains(asset.status) { throw HostingFailure(message: asset.error ?? "This upload is no longer available. Export again to create a new link.") }
        struct Saved: Decodable { let saved: Bool }
        let _: Saved = try await send(.init(route: "assets/\(asset.id)/details", token: request.token,
                                            body: JSONEncoder().encode(request.metadata.details)))
        if asset.status == "uploading" {
            guard let partBytes = asset.partBytes, (1...64 * 1024 * 1024).contains(partBytes),
                  let parts = asset.parts, parts == (bytes + partBytes - 1) / partBytes else {
                throw HostingFailure(message: "The upload configuration is invalid.")
            }
            let state: HostingAsset = try await send(.init(route: "assets/\(asset.id)", token: request.token, body: nil))
            let uploaded = state.uploadedParts ?? []
            let handle = try FileHandle(forReadingFrom: request.fileURL)
            defer { try? handle.close() }
            var sent = 0
            for number in 1...parts {
                try Task.checkCancellation()
                guard try HostingExportMetadata.fingerprint(request.fileURL) == key else {
                    throw HostingFailure(message: "The video changed during upload. Export it again before sharing.")
                }
                let offset = (number - 1) * partBytes
                let expected = min(partBytes, bytes - offset)
                if !uploaded.contains(where: { $0.number == number && $0.bytes == expected }) {
                    try handle.seek(toOffset: UInt64(offset))
                    var data = Data()
                    while data.count < expected {
                        guard let block = try handle.read(upToCount: expected - data.count), !block.isEmpty else {
                            throw HostingFailure(message: "The exported video is incomplete.")
                        }
                        data.append(block)
                    }
                    for attempt in 0...2 {
                        do {
                            struct SignedPart: Decodable { let url: URL }
                            let signed: SignedPart = try await send(.init(route: "assets/\(asset.id)/parts", token: request.token,
                                body: JSONSerialization.data(withJSONObject: ["number": number])))
                            guard signed.url.scheme == "https" ||
                                    (signed.url.host == origin.host && ["localhost", "127.0.0.1"].contains(origin.host ?? "")) else {
                                throw HostingFailure(message: "The upload requires a secure connection.")
                            }
                            var put = URLRequest(url: signed.url)
                            put.httpMethod = "PUT"
                            let (_, response) = try await session.upload(for: put, from: data)
                            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                                throw HostingFailure(message: "The upload was interrupted. Resume to continue from the saved parts.")
                            }
                            break
                        } catch {
                            try Task.checkCancellation()
                            if attempt == 2 { throw error }
                            try await Task.sleep(for: .seconds(1 << attempt))
                        }
                    }
                }
                sent += expected
                await request.progress(.uploading(Double(sent) / Double(bytes)))
            }
            guard try HostingExportMetadata.fingerprint(request.fileURL) == key else {
                throw HostingFailure(message: "The video changed during upload. Export it again before sharing.")
            }
            let _: HostingAsset = try await send(.init(route: "assets/\(asset.id)/complete", token: request.token, body: Data("{}".utf8)))
        }
        await request.progress(.processing)
        let deadline = ContinuousClock.now.advanced(by: .seconds(7200))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let status: HostingAsset = try await send(.init(route: "assets/\(asset.id)", token: request.token, body: nil))
            if status.status == "ready", let path = status.sharePath { return try shareURL(path) }
            if ["failed", "revoked"].contains(status.status) { throw HostingFailure(message: status.error ?? "The video could not be shared.") }
            try await Task.sleep(for: .seconds(3))
        }
        throw HostingFailure(message: "The video is still processing. Check again to retrieve the same link.")
    }
}

struct HostingCredentialStore {
    let origin: URL

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? "dev.blitzreels.blitzrecorder",
         kSecAttrAccount as String: "hosting:\(origin.absoluteString)"]
    }

    func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() { SecItemDelete(query as CFDictionary) }

    func save(_ token: String) throws {
        guard token.range(of: "^brh_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw HostingFailure(message: "Enter a valid hosting access key.")
        }
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw HostingFailure(message: "The hosting connection could not be saved in Keychain.") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw HostingFailure(message: "The hosting connection could not be saved in Keychain.")
        }
    }
}
