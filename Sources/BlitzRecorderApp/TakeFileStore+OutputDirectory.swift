import Foundation

extension TakeFileStore {
    static let minimumAvailableCapacityBytes: Int64 = 512 * 1024 * 1024

    func prepareOutputDirectory(settings: RecordingSettings) throws -> OutputDirectoryAccess {
        var seen: Set<URL> = []
        let locations = [settings.sourceStorage,
                         RecordingStorageLocation(url: settings.outputDirectory, bookmarkData: settings.outputDirectoryBookmarkData)]
            .filter { seen.insert($0.url.standardizedFileURL).inserted }
        let access = OutputDirectoryAccess(locations: locations)
        guard access.hasSecurityScopedAccess else {
            access.stop()
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: access.unavailableURL ?? settings.outputDirectory))
        }

        do {
            for location in locations {
                try prepareWritableDirectory(location.url)
            }

            let fileManager = FileManager.default
            let scratchRoot = scratchRoot(for: settings)
            try fileManager.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
            if let contents = try? fileManager.contentsOfDirectory(atPath: scratchRoot.path),
               contents.isEmpty {
                try? fileManager.removeItem(at: scratchRoot)
            }

            return access
        } catch let error as RecorderError {
            access.stop()
            throw error
        } catch {
            access.stop()
            throw RecorderError.outputDirectoryUnavailable(Self.outputDirectoryFailureMessage(error, url: settings.outputDirectory))
        }
    }

    private func prepareWritableDirectory(_ url: URL) throws {
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            let probeURL = url.appendingPathComponent(".write-test-\(UUID().uuidString)")
            try Data().write(to: probeURL, options: .atomic)
            try fileManager.removeItem(at: probeURL)
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            let capacity = Self.availableCapacityForRecording(
                importantUsageCapacity: values.volumeAvailableCapacityForImportantUsage,
                fallbackCapacity: values.volumeAvailableCapacity.map(Int64.init),
                fileSystemCapacity: Self.fileSystemAvailableCapacity(for: url))
            if let capacity, capacity < Self.minimumAvailableCapacityBytes {
                throw RecorderError.outputDirectoryUnavailable(
                    "\(url.lastPathComponent): \(Self.formattedByteCount(capacity)) available; at least 512 MB required")
            }
        } catch let error as RecorderError {
            throw error
        } catch {
            throw RecorderError.outputDirectoryUnavailable(Self.outputDirectoryFailureMessage(error, url: url))
        }
    }

    private static func outputDirectoryFailureMessage(_ error: Error, url: URL) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError) {
            return permissionRecoveryMessage(for: url)
        }

        let message = error.localizedDescription
        let lowercased = message.lowercased()
        if lowercased.contains("permission") || lowercased.contains("operation not permitted") {
            return permissionRecoveryMessage(for: url)
        }
        return message
    }

    static func permissionRecoveryMessage(for url: URL) -> String {
        "BlitzRecorder does not have permission to save to \(url.path). Choose this folder again in Export Settings, or pick another recording folder."
    }

    static func availableCapacityForRecording(
        importantUsageCapacity: Int64?,
        fallbackCapacity: Int64?,
        fileSystemCapacity: Int64? = nil
    ) -> Int64? {
        let reportedCapacities = [importantUsageCapacity, fallbackCapacity, fileSystemCapacity]
            .compactMap { $0 }
            .filter { $0 > 0 }
        if let capacity = reportedCapacities.max() {
            return capacity
        }
        return importantUsageCapacity ?? fallbackCapacity ?? fileSystemCapacity
    }

    private static func fileSystemAvailableCapacity(for url: URL) -> Int64? {
        guard let value = try? FileManager.default.attributesOfFileSystem(forPath: url.path)[.systemFreeSize] else {
            return nil
        }
        return (value as? NSNumber)?.int64Value
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
