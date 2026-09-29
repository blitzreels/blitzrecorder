import AVFoundation
import Foundation
import ImageIO
import Security
import UniformTypeIdentifiers

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
    var progress: Double? = nil
}

final class HostingRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct HostingClient {
    static let parallelParts = 6
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
        guard let bytes = values.fileSize, bytes >= 16, bytes <= 5 * 1024 * 1024 * 1024,
              fileURL.pathExtension.lowercased() == "mp4" else {
            throw HostingFailure(message: "Choose an exported video smaller than 5 GB.")
        }
        let duration = try await AVURLAsset(url: fileURL).load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 3600 else {
            throw HostingFailure(message: "Sharing supports videos up to one hour long.")
        }
        let key = try HostingExportMetadata.fingerprint(fileURL)
        let video = try await HostingSharingCopy.playable(fileURL)
        let body: [String: Any] = ["title": String(request.metadata.title.prefix(160)), "bytes": bytes,
            "duration": duration, "contentType": "video/mp4", "requestKey": key,
            "video": ["width": video.width, "height": video.height, "frameRate": video.frameRate.map { $0 as Any } ?? NSNull()]]
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
            if let poster = await HostingSharingCopy.poster(fileURL) {
                let _: Saved? = try? await send(.init(route: "assets/\(asset.id)/poster", token: request.token,
                    body: JSONSerialization.data(withJSONObject: ["jpeg": poster.base64EncodedString()])))
            }
            let state: HostingAsset = try await send(.init(route: "assets/\(asset.id)", token: request.token, body: nil))
            let uploaded = Set((state.uploadedParts ?? []).filter { part in
                (1...parts).contains(part.number) && part.bytes == min(partBytes, bytes - (part.number - 1) * partBytes)
            }.map(\.number))
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let sent = uploaded.reduce(0) { $0 + min(partBytes, bytes - ($1 - 1) * partBytes) }
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
                            throw HostingFailure(message: "The video changed during upload. Export it again before sharing.")
                        }
                        let offset = (number - 1) * partBytes
                        let expected = min(partBytes, bytes - offset)
                        try handle.seek(toOffset: UInt64(offset))
                        var data = Data()
                        while data.count < expected {
                            guard let block = try handle.read(upToCount: expected - data.count), !block.isEmpty else {
                                throw HostingFailure(message: "The exported video is incomplete.")
                            }
                            data.append(block)
                        }
                        let part = ChunkUpload(number: number, assetID: asset.id, token: request.token, data: data) { progress in
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
                throw HostingFailure(message: "The video changed during upload. Export it again before sharing.")
            }
            try Task.checkCancellation()
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
        let number: Int
        let assetID: String
        let token: String
        let data: Data
        let progress: @Sendable (Progress) async -> Void
    }

    private func uploadChunk(_ part: ChunkUpload) async throws {
        for attempt in 0...2 {
            try Task.checkCancellation()
            do {
                struct SignedPart: Decodable { let url: URL }
                let signed: SignedPart = try await send(.init(route: "assets/\(part.assetID)/parts", token: part.token,
                    body: JSONSerialization.data(withJSONObject: ["number": part.number])))
                guard signed.url.scheme == "https" ||
                        (signed.url.host == origin.host && ["localhost", "127.0.0.1"].contains(origin.host ?? "")) else {
                    throw HostingFailure(message: "The upload requires a secure connection.")
                }
                var put = URLRequest(url: signed.url)
                put.httpMethod = "PUT"
                let response = try await uploadPart(.init(request: put, data: part.data,
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

    private func uploadPart(_ part: PartUpload) async throws -> URLResponse {
        let updates = AsyncStream<Int64>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let delegate = HostingUploadDelegate(continuation: updates.continuation)
        let observer = Task {
            for await bytes in updates.stream {
                await part.progress(.uploading(.init(
                    sent: part.completedBytes + min(Int64(part.data.count), max(0, bytes)), total: part.totalBytes)))
            }
        }
        do {
            let (_, response) = try await session.upload(for: part.request, from: part.data, delegate: delegate)
            updates.continuation.finish()
            await observer.value
            return response
        } catch {
            updates.continuation.finish()
            await observer.value
            throw error
        }
    }
}

enum HostingSharingCopy {
    struct Request {
        let fileURL: URL
        let progress: @Sendable (HostingClient.Progress) async -> Void
    }

    static func prepare(_ request: Request) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: request.fileURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 3600,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw HostingFailure(message: "Sharing supports videos up to one hour long.")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let displaySize = bounds.size
        let codec = try await track.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        var audioIsAAC = true
        for audio in try await asset.loadTracks(withMediaType: .audio) {
            let format = try await audio.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
            audioIsAAC = audioIsAAC && format == kAudioFormatMPEG4AAC
        }
        let browserReady = min(displaySize.width, displaySize.height) <= 1080 && max(displaySize.width, displaySize.height) <= 1920
            && codec == kCMVideoCodecType_H264 && audioIsAAC
        if browserReady, request.fileURL.pathExtension.lowercased() == "mp4" { return request.fileURL }
        let fingerprint = try HostingExportMetadata.fingerprint(request.fileURL)
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("BlitzRecorder/Sharing1080-h264-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent(fingerprint).appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        let output = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        guard let exporter = AVAssetExportSession(asset: asset,
            presetName: browserReady ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality) else {
            throw HostingFailure(message: "This video could not be prepared for sharing.")
        }
        if !browserReady {
            let scale = min(1, 1080 / min(displaySize.width, displaySize.height), 1920 / max(displaySize.width, displaySize.height))
            let renderSize = CGSize(width: max(2, floor(displaySize.width * scale / 2) * 2),
                                    height: max(2, floor(displaySize.height * scale / 2) * 2))
            let composition = AVMutableVideoComposition()
            composition.renderSize = renderSize
            let frameDuration = try await track.load(.minFrameDuration)
            let fps = try await track.load(.nominalFrameRate)
            composition.frameDuration = frameDuration.isNumeric && frameDuration.seconds > 0
                ? frameDuration : CMTime(seconds: 1 / Double(max(1, fps)), preferredTimescale: 60_000)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
            instruction.layerInstructions = [layer]
            composition.instructions = [instruction]
            exporter.videoComposition = composition
        }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.metadata = []
        await request.progress(.optimizing(0))
        let progressTask = Task {
            while !Task.isCancelled {
                await request.progress(.optimizing(Double(exporter.progress)))
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            }
        }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await exporter.export(to: output, as: .mp4)
            } onCancel: { exporter.cancelExport() }
            progressTask.cancel()
            await progressTask.value
            try Task.checkCancellation()
            guard try HostingExportMetadata.fingerprint(request.fileURL) == fingerprint else {
                throw HostingFailure(message: "The video changed while preparing the sharing copy. Try again.")
            }
            if FileManager.default.fileExists(atPath: cached.path) {
                try FileManager.default.removeItem(at: output)
            } else {
                try FileManager.default.moveItem(at: output, to: cached)
            }
            await request.progress(.optimizing(1))
            return cached
        } catch {
            progressTask.cancel()
            await progressTask.value
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    struct Playable: Equatable {
        let width: Int
        let height: Int
        let frameRate: Double?
    }

    static func playable(_ fileURL: URL) async throws -> Playable {
        guard let track = try await AVURLAsset(url: fileURL).loadTracks(withMediaType: .video).first else {
            throw HostingFailure(message: "This video could not be prepared for sharing.")
        }
        let (size, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let display = CGRect(origin: .zero, size: size).applying(transform).size
        return Playable(width: Int(display.width.rounded()), height: Int(display.height.rounded()),
                        frameRate: fps > 0 && fps <= 240 ? Double(fps) : nil)
    }

    static func poster(_ fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite,
              let image = try? await generator.image(at: CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)).image else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= 1024 * 1024 else { return nil }
        return data as Data
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

final class HostingUploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
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
