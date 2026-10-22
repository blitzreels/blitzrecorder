import AVFoundation
import Foundation
import Security

struct HostingFailure: LocalizedError {
    let message: String
    var status: Int? = nil
    var errorDescription: String? { message }
}

struct HostingPlan: Codable {
    let name: String
    let amount: Int
    let currency: String
    let storageBytes: Int64
    let uploadSeconds: Int
    let uploadWindowDays: Int
    let maximumResolution: Int
    let retentionDaysAfterExpiry: Int
    /// The paid plan can be bought.
    let available: Bool
    /// Free sharing from the user's own Cloudflare account. Older servers omit it.
    let ownStorage: Bool?

    var price: String {
        (Double(amount) / 100).formatted(.currency(code: currency.uppercased()).precision(.fractionLength(0)))
    }

    var allowance: String {
        "\(storageBytes / 1_000_000_000) GB storage · \(uploadSeconds / 3600) hours uploaded per \(uploadWindowDays) days"
    }

    var offersSharing: Bool { available || ownStorage == true }
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
    var progress: Double? = nil
}

class HostingRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

extension URL {
    var hasLocalDevelopmentHost: Bool { ["localhost", "127.0.0.1"].contains(host ?? "") }
}

struct HostingClient {
    static let parallelParts = 6
    let origin: URL
    let session: URLSession

    static var configured: Self {
        var origin = URL(string: "https://blitzrecorder.com")!
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "HostingOrigin"), let local = URL(string: value),
           local.hasLocalDevelopmentHost, ["http", "https"].contains(local.scheme ?? "") {
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
        var method: String { body == nil ? "GET" : "POST" }
    }

    private struct Failure: Decodable { let error: String }

    func send<T: Decodable>(_ request: Request) async throws -> T {
        try await send(request, method: request.method)
    }

    func delete<T: Decodable>(_ request: Request) async throws -> T {
        try await send(request, method: "DELETE")
    }

    private func send<T: Decodable>(_ request: Request, method: String) async throws -> T {
        let url = origin.appendingPathComponent("api/hosting").appendingPathComponent(request.route)
        var http = URLRequest(url: url)
        http.httpMethod = method
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

    enum Destination: Sendable {
        case blitzrecorder
        case cloudflare(CloudflareStorageConnection)
    }
    struct Upload {
        let fileURL: URL
        let token: String
        let metadata: HostingExportMetadata
        let destination: Destination
        let progress: @Sendable (Progress) async -> Void
    }
    enum Progress: Sendable, Equatable {
        case optimizing(Double)
        case preparing
        case uploading(HostingUploadBytes)
        case processing(Double?)

        var isProcessing: Bool {
            if case .processing = self { return true }
            return false
        }
    }

    func upload(_ request: Upload) async throws -> URL {
        await request.progress(.preparing)
        let fileURL = try await HostingSharingCopy.prepare(.init(fileURL: request.fileURL, progress: request.progress))
        await request.progress(.preparing)
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let bytes = values.fileSize, bytes >= 16, fileURL.pathExtension.lowercased() == "mp4" else {
            throw HostingFailure(message: "Choose an exported MP4 video.")
        }
        let duration = try await AVURLAsset(url: fileURL).load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw HostingFailure(message: "This video has no playable duration.")
        }
        let key = try HostingExportMetadata.fingerprint(fileURL)
        let video = try await HostingSharingCopy.playable(fileURL)
        var media: CloudflareMediaClient?
        if case .cloudflare(let connection) = request.destination { media = .init(connection: connection, session: session) }
        var body: [String: Any] = ["title": String(request.metadata.title.prefix(160)), "bytes": bytes,
            "duration": duration, "contentType": "video/mp4", "requestKey": key,
            "video": ["width": video.width, "height": video.height, "frameRate": video.frameRate.map { $0 as Any } ?? NSNull()]]
        if let media { body["mediaOrigin"] = media.connection.mediaOrigin.absoluteString }
        let asset: HostingAsset = try await send(.init(route: "assets", token: request.token,
            body: JSONSerialization.data(withJSONObject: body)))
        guard UUID(uuidString: asset.id) != nil else { throw HostingFailure(message: "The upload could not be created.") }
        if asset.status == "ready", let path = asset.sharePath { return try shareURL(path) }
        if ["failed", "revoked"].contains(asset.status) { throw HostingFailure(message: asset.error ?? "This upload is no longer available. Export again to create a new link.") }
        struct Saved: Decodable { let saved: Bool }
        // Transcript problems never block sharing the video.
        let _: Saved? = try? await send(.init(route: "assets/\(asset.id)/details", token: request.token,
                                              body: JSONEncoder().encode(request.metadata.details)))
        if asset.status == "uploading" {
            guard let partBytes = asset.partBytes, (1...64 * 1024 * 1024).contains(partBytes),
                  let parts = asset.parts, parts == (bytes + partBytes - 1) / partBytes else {
                throw HostingFailure(message: "The upload configuration is invalid.")
            }
            func partSize(_ number: Int) -> Int { min(partBytes, bytes - (number - 1) * partBytes) }
            let changedDuringUpload = HostingFailure(message: "The video changed during upload. Export it again before sharing.")
            let journal = CloudflareUploadJournal(assetID: asset.id)
            let uploaded: Set<Int>
            if let media {
                if let poster = await HostingSharingCopy.poster(fileURL) {
                    try? await media.putPoster(assetID: asset.id, jpeg: poster)
                }
                if await journal.uploadID == nil {
                    await journal.start(uploadID: try await media.createUpload(assetID: asset.id))
                }
                uploaded = Set(await journal.parts.map(\.part).filter { (1...parts).contains($0) })
            } else {
                if let poster = await HostingSharingCopy.poster(fileURL) {
                    let _: Saved? = try? await send(.init(route: "assets/\(asset.id)/poster", token: request.token,
                        body: JSONSerialization.data(withJSONObject: ["jpeg": poster.base64EncodedString()])))
                }
                let state: HostingAsset = try await send(.init(route: "assets/\(asset.id)", token: request.token, body: nil))
                uploaded = Set((state.uploadedParts ?? []).filter { part in
                    (1...parts).contains(part.number) && part.bytes == partSize(part.number)
                }.map(\.number))
            }
            let cloudflareUploadID = await journal.uploadID
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let sent = uploaded.reduce(0) { $0 + partSize($1) }
            let updates = AsyncStream<Progress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let aggregate = HostingMultipartProgress(.init(sent: Int64(sent), total: Int64(bytes), continuation: updates.continuation))
            let observer = Task {
                for await progress in updates.stream { await request.progress(progress) }
            }
            await request.progress(.uploading(.init(sent: Int64(sent), total: Int64(bytes))))
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    var active = 0
                    for number in 1...parts where !uploaded.contains(number) {
                        if active == Self.parallelParts {
                            try await group.next()
                            active -= 1
                        }
                        try Task.checkCancellation()
                        guard try HostingExportMetadata.fingerprint(fileURL) == key else {
                            throw changedDuringUpload
                        }
                        let expected = partSize(number)
                        try handle.seek(toOffset: UInt64((number - 1) * partBytes))
                        var data = Data()
                        while data.count < expected {
                            guard let block = try handle.read(upToCount: expected - data.count), !block.isEmpty else {
                                throw HostingFailure(message: "The exported video is incomplete.")
                            }
                            data.append(block)
                        }
                        let target: ChunkUpload.Target = if let media, let cloudflareUploadID {
                            .cloudflare(media.partRequest(assetID: asset.id, uploadID: cloudflareUploadID, number: number), journal)
                        } else { .blitzrecorder }
                        let part = ChunkUpload(number: number, assetID: asset.id, token: request.token, data: data, target: target) { progress in
                            guard case .uploading(let bytes) = progress else { return }
                            await aggregate.record(.init(number: number, sent: bytes.sent, expected: Int64(expected)))
                        }
                        group.addTask {
                            try await uploadChunk(part)
                            await aggregate.record(.init(number: number, sent: Int64(expected), expected: Int64(expected)))
                        }
                        active += 1
                    }
                    try await group.waitForAll()
                }
                updates.continuation.finish()
                await observer.value
            } catch {
                updates.continuation.finish()
                await observer.value
                throw error
            }
            guard try HostingExportMetadata.fingerprint(fileURL) == key else {
                throw changedDuringUpload
            }
            try Task.checkCancellation()
            if let media, let cloudflareUploadID {
                do {
                    try await media.complete(assetID: asset.id, uploadID: cloudflareUploadID, parts: await journal.parts)
                } catch {
                    await journal.clear()
                    throw HostingFailure(message: "Your Cloudflare storage couldn’t finish this upload. Share again to start a fresh upload.")
                }
                await journal.clear()
            }
            let completed: HostingAsset = try await send(.init(route: "assets/\(asset.id)/complete", token: request.token, body: Data("{}".utf8)))
            if completed.status == "ready", let path = completed.sharePath { return try shareURL(path) }
        }
        var reported: Double?
        await request.progress(.processing(nil))
        let deadline = ContinuousClock.now.advanced(by: .seconds(7200))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let status: HostingAsset = try await send(.init(route: "assets/\(asset.id)", token: request.token, body: nil))
            if status.status == "ready", let path = status.sharePath { return try shareURL(path) }
            if ["failed", "revoked"].contains(status.status) { throw HostingFailure(message: status.error ?? "The video could not be shared.") }
            if let fraction = status.progress.map({ min(max($0, 0), 1) }), fraction != reported {
                reported = fraction
                await request.progress(.processing(fraction))
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw HostingFailure(message: "The video is still processing. Check again to retrieve the same link.")
    }

    private struct ChunkUpload {
        enum Target {
            case blitzrecorder
            case cloudflare(URLRequest, CloudflareUploadJournal)
        }
        let number: Int
        let assetID: String
        let token: String
        let data: Data
        let target: Target
        let progress: @Sendable (Progress) async -> Void
    }

    private func uploadChunk(_ part: ChunkUpload) async throws {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                if case .cloudflare(let put, let journal) = part.target {
                    let (data, response) = try await uploadPart(.init(request: put, data: part.data,
                        completedBytes: 0, totalBytes: Int64(part.data.count), progress: part.progress))
                    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                          let saved = try? JSONDecoder().decode(CloudflareMediaClient.UploadedPart.self, from: data),
                          saved.part == part.number else {
                        throw HostingFailure(message: "The upload to your Cloudflare storage was interrupted. Resume to continue.")
                    }
                    await journal.record(saved)
                    return
                }
                struct SignedPart: Decodable { let url: URL }
                let signed: SignedPart = try await send(.init(route: "assets/\(part.assetID)/parts", token: part.token,
                    body: JSONSerialization.data(withJSONObject: ["number": part.number])))
                guard signed.url.scheme == "https" ||
                        (signed.url.host == origin.host && origin.hasLocalDevelopmentHost) else {
                    throw HostingFailure(message: "The upload requires a secure connection.")
                }
                var put = URLRequest(url: signed.url)
                put.httpMethod = "PUT"
                let (_, response) = try await uploadPart(.init(request: put, data: part.data,
                    completedBytes: 0, totalBytes: Int64(part.data.count), progress: part.progress))
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                    throw HostingFailure(message: "The upload was interrupted. Resume to continue from the saved parts.")
                }
                return
            } catch {
                try Task.checkCancellation()
                if attempt == 2 { throw error }
                try await Task.sleep(for: .seconds(1 << attempt))
            }
        }
    }

    private struct PartUpload {
        let request: URLRequest
        let data: Data
        let completedBytes: Int64
        let totalBytes: Int64
        let progress: @Sendable (Progress) async -> Void
    }

    private func uploadPart(_ part: PartUpload) async throws -> (Data, URLResponse) {
        let updates = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let delegate = HostingUploadDelegate(continuation: updates.continuation)
        let observer = Task {
            for await bytes in updates.stream {
                await part.progress(.uploading(.init(
                    sent: part.completedBytes + min(Int64(part.data.count), max(0, bytes)), total: part.totalBytes)))
            }
        }
        do {
            let (data, response) = try await session.upload(for: part.request, from: part.data, delegate: delegate)
            updates.continuation.finish()
            await observer.value
            return (data, response)
        } catch {
            updates.continuation.finish()
            await observer.value
            throw error
        }
    }
}

struct HostingUploadBytes: Sendable, Equatable {
    let sent: Int64
    let total: Int64

    var fraction: Double { total > 0 ? min(1, max(0, Double(sent) / Double(total))) : 0 }
    var detail: String {
        let sentText = ByteCountFormatter.string(fromByteCount: min(total, max(0, sent)), countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return "\(sentText) of \(totalText)"
    }
}

final class HostingUploadDelegate: HostingRedirectPolicy, @unchecked Sendable {
    private let continuation: AsyncStream<Int64>.Continuation
    private let lock = NSLock()
    private var lastUpdate = ContinuousClock.now

    init(continuation: AsyncStream<Int64>.Continuation) { self.continuation = continuation }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.withLock {
            let now = ContinuousClock.now
            guard now - lastUpdate >= .milliseconds(100) || totalBytesSent >= totalBytesExpectedToSend else { return }
            lastUpdate = now
            continuation.yield(totalBytesSent)
        }
    }
}

struct HostingCredentialStore {
    let origin: URL

    private var item: KeychainItem { .init(account: "hosting:\(origin.absoluteString)") }

    func load() -> String? { item.load().flatMap { String(data: $0, encoding: .utf8) } }

    func clear() { item.clear() }

    func save(_ token: String) throws {
        guard token.range(of: "^brh_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw HostingFailure(message: "Enter a valid hosting access key.")
        }
        guard item.save(Data(token.utf8)) else {
            throw HostingFailure(message: "The hosting connection could not be saved in Keychain.")
        }
    }
}

actor HostingMultipartProgress {
    struct Configuration {
        let sent: Int64
        let total: Int64
        let continuation: AsyncStream<HostingClient.Progress>.Continuation
    }
    struct Update {
        let number: Int
        let sent: Int64
        let expected: Int64
    }
    private let configuration: Configuration
    private var sent: Int64
    private var parts: [Int: Int64] = [:]

    init(_ configuration: Configuration) {
        self.configuration = configuration
        sent = configuration.sent
    }

    func record(_ update: Update) {
        let previous = parts[update.number, default: 0]
        let current = max(previous, min(update.expected, max(0, update.sent)))
        guard current > previous else { return }
        parts[update.number] = current
        sent += current - previous
        configuration.continuation.yield(.uploading(.init(sent: min(configuration.total, sent), total: configuration.total)))
    }
}
