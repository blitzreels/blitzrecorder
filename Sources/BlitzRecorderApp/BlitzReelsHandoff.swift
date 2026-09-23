import AppKit
import CryptoKit
import Observation

struct BlitzReelsUploadInit: Decodable { let upload_url: URL; let storage_key: String }
struct BlitzReelsUploadResult: Decodable { let id: String; let processing_status: String }

struct BlitzReelsHandoffRecord: Codable {
    let fingerprint: String
    let organizationID: String
    let userID: String
    let origin: String
    let storageKey: String
    let idempotencyKey: String
    let fileName: String
    var uploaded: Bool
    var assetID: String?
}

struct BlitzReelsSendRequest {
    let fileURL: URL
    let project: RecordingProject
    let settings: RecordingSettings
}

enum BlitzReelsExportFiles {
    static func files(_ project: RecordingProject) -> [URL] {
        let paths = project.exports.sorted { $0.createdAt > $1.createdAt }.map(\.path)
            + (project.finalVideoPath.map { [$0] } ?? [])
        let sourcePaths = Set(project.sources.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        var seen = Set<String>()
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension.lowercased() == "mp4", !sourcePaths.contains(url.standardizedFileURL.path),
                  seen.insert(url.standardizedFileURL.path).inserted,
                  FileManager.default.isReadableFile(atPath: path) else { return nil }
            return url
        }
    }

    static func fingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
@Observable
final class BlitzReelsHandoffController {
    static let shared = BlitzReelsHandoffController()
    let connection = BlitzReelsConnection(client: .configured)
    private(set) var projectID: UUID?
    private(set) var selectedExportURL: URL?
    private(set) var status = ""
    private(set) var isWorking = false
    private(set) var progress: Double?
    private(set) var createURL: URL?
    private(set) var upgradeURL: URL?
    private(set) var setupURL: URL?
    @ObservationIgnored private var task: Task<Void, Never>?

    func selectExport(_ request: BlitzReelsSendRequest) {
        guard !isWorking else { return }
        if projectID != request.project.id || selectedExportURL != request.fileURL {
            createURL = nil
            status = ""
        }
        projectID = request.project.id
        selectedExportURL = request.fileURL
    }

    func cancel() { task?.cancel() }

    func selectWorkspace(_ id: String) {
        guard !isWorking else { return }
        connection.selectWorkspace(id)
        createURL = nil
        status = ""
    }

    func connect() {
        perform {
            self.status = "Sign in through your browser to connect BlitzReels."
            try await self.connection.connect()
            self.status = "Connected. Choose a workspace and send your MP4."
        }
    }

    func restoreConnection() async {
        guard !isWorking, connection.hasCredential, connection.account == nil else { return }
        do { try await connection.reload() }
        catch {
            if case BlitzReelsHandoffError.accountSetup = error {
                setupURL = connection.client.origin.appendingPathComponent("dashboard/onboarding")
            }
            status = error.localizedDescription
        }
    }

    func disconnect() {
        perform {
            self.status = "Disconnecting…"
            try await self.connection.disconnect()
            self.createURL = nil
            self.status = "Disconnected from BlitzReels."
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        upgradeURL = nil
        setupURL = nil
        task = Task {
            defer { isWorking = false; progress = nil; task = nil }
            do { try await operation() }
            catch is CancellationError { status = "Cancelled. Your exported video is still on this Mac." }
            catch let error as URLError where error.code == .cancelled {
                status = "Cancelled. Your exported video is still on this Mac."
            }
            catch {
                if case BlitzReelsHandoffError.accountSetup = error {
                    setupURL = connection.client.origin.appendingPathComponent("dashboard/onboarding")
                }
                if case BlitzReelsHandoffError.planAccess = error,
                   let id = connection.selectedWorkspaceID {
                    upgradeURL = connection.client.origin.appendingPathComponent("dashboard/workspaces/\(id)/billing")
                }
                status = error.localizedDescription
            }
        }
    }

    func send(_ request: BlitzReelsSendRequest) {
        guard !isWorking else { return }
        selectExport(request)
        createURL = nil
        perform { try await self.upload(request) }
    }

    private func upload(_ request: BlitzReelsSendRequest) async throws {
        guard request.fileURL.pathExtension.lowercased() == "mp4",
              BlitzReelsExportFiles.files(request.project).contains(request.fileURL) else {
            throw BlitzReelsHandoffError.exportRequired
        }
        let access = try TakeFileStore().prepareOutputDirectory(settings: request.settings)
        defer { access.stop() }
        let scoped = request.fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { request.fileURL.stopAccessingSecurityScopedResource() } }
        let size = Int64(try request.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 0 && size <= 5 * 1024 * 1024 * 1024 else { throw BlitzReelsHandoffError.fileSize }
        let chosenWorkspace = connection.selectedWorkspaceID
        try await connection.reload()
        guard let workspace = connection.selectedWorkspace,
              let userID = connection.account?.user.id,
              chosenWorkspace == workspace.id else { throw BlitzReelsHandoffError.workspaceAccess }
        status = "Preparing \(request.fileURL.lastPathComponent)…"
        let hashTask = Task.detached { try BlitzReelsExportFiles.fingerprint(request.fileURL) }
        let fingerprint = try await withTaskCancellationHandler { try await hashTask.value } onCancel: { hashTask.cancel() }
        try Task.checkCancellation()
        let receiptURL = URL(fileURLWithPath: request.project.takeDirectoryPath).appendingPathComponent("blitzreels-exports.json")
        var receipts = (try? JSONDecoder().decode([BlitzReelsHandoffRecord].self, from: Data(contentsOf: receiptURL))) ?? []
        let origin = connection.client.origin.absoluteString
        var receipt = receipts.first {
            $0.fingerprint == fingerprint && $0.organizationID == workspace.id && $0.userID == userID && $0.origin == origin
        }

        func save(_ record: BlitzReelsHandoffRecord) throws {
            receipts.removeAll {
                $0.fingerprint == fingerprint && $0.organizationID == workspace.id && $0.userID == userID && $0.origin == origin
            }
            receipts.append(record)
            try JSONEncoder().encode(receipts).write(to: receiptURL, options: .atomic)
        }

        if let id = receipt?.assetID {
            do {
                let _: BlitzReelsUploadResult = try await connection.send(.init(
                    path: "api/blitzrecorder/media/\(id)?organization_id=\(workspace.id)", method: "GET", key: nil, body: nil
                ))
                finish(.init(assetID: id, organizationID: workspace.id))
                return
            } catch BlitzReelsHandoffError.missingAsset {
                receipt = nil
            }
        }

        let name = receipt?.fileName ?? (String(request.fileURL.deletingPathExtension().lastPathComponent.prefix(190)) + ".mp4")
        let identity = receipt?.idempotencyKey ?? "recorder-\(UUID().uuidString)"
        if receipt?.uploaded != true {
            status = "Preparing upload to \(workspace.name)…"
            let upload: BlitzReelsUploadInit = try await connection.send(.init(
                path: "api/blitzrecorder/media/upload/init", method: "POST", key: nil,
                body: ["organization_id": workspace.id, "file_name": name, "content_type": "video/mp4", "file_size_bytes": size],
                idempotencyKey: identity
            ))
            guard upload.upload_url.scheme == "https"
                || (["localhost", "127.0.0.1"].contains(upload.upload_url.host ?? "")
                    && ["localhost", "127.0.0.1"].contains(connection.client.origin.host ?? "")) else {
                throw BlitzReelsHandoffError.invalidResponse
            }
            receipt = .init(fingerprint: fingerprint, organizationID: workspace.id, userID: userID, origin: origin,
                            storageKey: upload.storage_key, idempotencyKey: identity, fileName: name, uploaded: false, assetID: nil)
            try save(receipt!)
            status = "Uploading \(name)…"
            var put = URLRequest(url: upload.upload_url)
            put.httpMethod = "PUT"
            put.timeoutInterval = 3600
            put.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            let delegate = BlitzReelsUploadProgress { [weak self] fraction in
                Task { @MainActor in self?.progress = fraction }
            }
            let (data, response) = try await connection.client.session.upload(for: put, fromFile: request.fileURL, delegate: delegate)
            try BlitzReelsHTTPClient.validate(.init(data: data, response: response))
            receipt!.uploaded = true
            try save(receipt!)
        }
        try Task.checkCancellation()
        status = "Saving your video in BlitzReels…"
        let result: BlitzReelsUploadResult = try await connection.send(.init(
            path: "api/blitzrecorder/media/upload/finalize", method: "POST", key: nil,
            body: ["organization_id": workspace.id, "storage_key": receipt!.storageKey,
                   "file_name": name, "content_type": "video/mp4", "file_size_bytes": size],
            idempotencyKey: identity
        ))
        receipt!.assetID = result.id
        try save(receipt!)
        try Task.checkCancellation()
        finish(.init(assetID: result.id, organizationID: workspace.id))
    }

    private func finish(_ request: BlitzReelsHTTPClient.CreateURLRequest) {
        let url = connection.client.createURL(request)
        createURL = url
        status = "Uploaded. Choose captions and optional B-roll in BlitzReels."
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
    case invalidResponse, signInAgain, workspaceAccess, rateLimited, keychain, fileAccess, fileSize, authorization
    case exportRequired, missingAsset
    case planAccess(String), accountSetup(String), server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "BlitzReels returned an unexpected response. Try again."
        case .signInAgain: "Your BlitzReels connection expired. Connect again to continue."
        case .workspaceAccess: "Choose a workspace you can access before sending this export."
        case .rateLimited: "BlitzReels is busy. Try again in a moment."
        case .keychain: "The connection could not be saved securely in Keychain."
        case .fileAccess: "This file is no longer accessible. Export it again to a folder BlitzRecorder can access."
        case .fileSize: "Choose a non-empty MP4 up to 5 GB. Export a smaller version for larger videos."
        case .authorization: "BlitzReels sign-in could not be completed. Connect again to retry."
        case .exportRequired: "Export an MP4 first, then send that exported video to BlitzReels."
        case .missingAsset: "This uploaded video is no longer available. Send the export again."
        case .planAccess(let message), .accountSetup(let message), .server(let message): message
        }
    }
}
