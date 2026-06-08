import Foundation

enum RemoteCameraImportPhase: String, Codable, Equatable {
    case waitingForStop
    case ready
    case transferring
    case complete
    case failedRecoverable
    case failedUnrecoverable
}

struct RemoteCameraPendingImport: Codable, Equatable {
    var takeID: UUID
    var serviceID: String?
    var scratchDirectory: URL
    var destinationURL: URL
    var createdAt: Date
    var expectedByteCount: Int64?
    var phase: RemoteCameraImportPhase

    init(
        takeID: UUID,
        serviceID: String?,
        scratchDirectory: URL,
        destinationURL: URL,
        createdAt: Date,
        expectedByteCount: Int64?,
        phase: RemoteCameraImportPhase = .waitingForStop
    ) {
        self.takeID = takeID
        self.serviceID = serviceID
        self.scratchDirectory = scratchDirectory
        self.destinationURL = destinationURL
        self.createdAt = createdAt
        self.expectedByteCount = expectedByteCount
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey {
        case takeID
        case serviceID
        case scratchDirectory
        case destinationURL
        case createdAt
        case expectedByteCount
        case phase
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takeID = try container.decode(UUID.self, forKey: .takeID)
        serviceID = try container.decodeIfPresent(String.self, forKey: .serviceID)
        scratchDirectory = try container.decode(URL.self, forKey: .scratchDirectory)
        destinationURL = try container.decode(URL.self, forKey: .destinationURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expectedByteCount = try container.decodeIfPresent(Int64.self, forKey: .expectedByteCount)
        phase = try container.decodeIfPresent(RemoteCameraImportPhase.self, forKey: .phase) ?? .waitingForStop
    }
}

enum RemoteCameraTakeIDResolver {
    static func takeID(
        activeTakeID: UUID?,
        pendingTransferDestinationURLs: [UUID: URL],
        pendingImports: [RemoteCameraPendingImport],
        take: RecordingTake
    ) -> UUID? {
        if let activeTakeID {
            return activeTakeID
        }

        let cameraPath = take.cameraURL.standardizedFileURL.path
        if let pendingTransfer = pendingTransferDestinationURLs.first(where: {
            $0.value.standardizedFileURL.path == cameraPath
        }) {
            return pendingTransfer.key
        }

        let scratchPath = take.scratchDirectory.standardizedFileURL.path
        return pendingImports.first(where: {
            $0.destinationURL.standardizedFileURL.path == cameraPath
                || $0.scratchDirectory.standardizedFileURL.path == scratchPath
        })?.takeID
    }
}

struct RemoteCameraPendingImportStore {
    func all(settings: RecordingSettings) -> [RemoteCameraPendingImport] {
        guard let data = try? Data(contentsOf: indexURL(settings: settings)) else {
            return []
        }
        return (try? JSONDecoder().decode([RemoteCameraPendingImport].self, from: data)) ?? []
    }

    func upsert(_ pendingImport: RemoteCameraPendingImport, settings: RecordingSettings) {
        var imports = all(settings: settings)
        if let index = imports.firstIndex(where: { $0.takeID == pendingImport.takeID }) {
            imports[index] = pendingImport
        } else {
            imports.append(pendingImport)
        }
        save(imports, settings: settings)
    }

    func remove(takeID: UUID, settings: RecordingSettings) {
        let imports = all(settings: settings).filter { $0.takeID != takeID }
        save(imports, settings: settings)
    }

    func updateExpectedByteCount(takeID: UUID, expectedByteCount: Int64, settings: RecordingSettings) {
        var imports = all(settings: settings)
        guard let index = imports.firstIndex(where: { $0.takeID == takeID }) else { return }
        imports[index].expectedByteCount = expectedByteCount
        save(imports, settings: settings)
    }

    func updatePhase(takeID: UUID, phase: RemoteCameraImportPhase, settings: RecordingSettings) {
        var imports = all(settings: settings)
        guard let index = imports.firstIndex(where: { $0.takeID == takeID }) else { return }
        imports[index].phase = phase
        save(imports, settings: settings)
    }

    private func save(_ imports: [RemoteCameraPendingImport], settings: RecordingSettings) {
        let url = indexURL(settings: settings)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(imports)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Recovery metadata is best effort; the active recording path must not fail because this sidecar write failed.
        }
    }

    private func indexURL(settings: RecordingSettings) -> URL {
        settings.outputDirectory
            .appendingPathComponent(".BlitzRecorderScratch", isDirectory: true)
            .appendingPathComponent("remote-camera-pending-imports.json")
    }
}
