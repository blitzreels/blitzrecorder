import Foundation

struct RemoteCameraPendingImport: Codable, Equatable {
    var takeID: UUID
    var serviceID: String?
    var scratchDirectory: URL
    var destinationURL: URL
    var createdAt: Date
    var expectedByteCount: Int64?
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
