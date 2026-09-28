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
        var seen: Set<UUID> = []
        return settings.projectLibraries.flatMap { location in
            let access = OutputDirectoryAccess(locations: [location])
            defer { access.stop() }
            guard access.hasSecurityScopedAccess else { return [RemoteCameraPendingImport]() }
            var localSettings = settings
            localSettings.projectLibrary = location
            return localImports(settings: localSettings)
        }.filter { seen.insert($0.takeID).inserted }
    }

    private func localImports(settings: RecordingSettings) -> [RemoteCameraPendingImport] {
        guard let data = try? Data(contentsOf: indexURL(settings: settings)) else {
            return []
        }
        return (try? JSONDecoder().decode([RemoteCameraPendingImport].self, from: data)) ?? []
    }

    func upsert(_ pendingImport: RemoteCameraPendingImport, settings: RecordingSettings) {
        let root = pendingImport.scratchDirectory.deletingLastPathComponent().deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        var settings = settings
        if let owner = settings.projectLibraries.first(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == root }) {
            settings.projectLibrary = owner
        }
        let access = OutputDirectoryAccess(locations: [settings.sourceStorage])
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else { return }
        var imports = localImports(settings: settings)
        if let index = imports.firstIndex(where: { $0.takeID == pendingImport.takeID }) {
            imports[index] = pendingImport
        } else {
            imports.append(pendingImport)
        }
        save(imports, settings: settings)
    }

    func remove(takeID: UUID, settings: RecordingSettings) {
        updateLibraries(.init(settings: settings, mutate: { $0.removeAll { $0.takeID == takeID } }))
    }

    func updateExpectedByteCount(takeID: UUID, expectedByteCount: Int64, settings: RecordingSettings) {
        updateLibraries(.init(settings: settings, mutate: { imports in
            guard let index = imports.firstIndex(where: { $0.takeID == takeID }) else { return }
            imports[index].expectedByteCount = expectedByteCount
        }))
    }

    func updatePhase(takeID: UUID, phase: RemoteCameraImportPhase, settings: RecordingSettings) {
        updateLibraries(.init(settings: settings, mutate: { imports in
            guard let index = imports.firstIndex(where: { $0.takeID == takeID }) else { return }
            imports[index].phase = phase
        }))
    }

    private struct LibraryUpdate {
        let settings: RecordingSettings
        let mutate: (inout [RemoteCameraPendingImport]) -> Void
    }

    private func updateLibraries(_ request: LibraryUpdate) {
        for location in request.settings.projectLibraries {
            let access = OutputDirectoryAccess(locations: [location])
            defer { access.stop() }
            guard access.hasSecurityScopedAccess else { continue }
            var settings = request.settings
            settings.projectLibrary = location
            var imports = localImports(settings: settings)
            let previous = imports
            request.mutate(&imports)
            if imports != previous { save(imports, settings: settings) }
        }
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
        settings.sourceStorage.url
            .appendingPathComponent(".BlitzRecorderScratch", isDirectory: true)
            .appendingPathComponent("remote-camera-pending-imports.json")
    }
}
