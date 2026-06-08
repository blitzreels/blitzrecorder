import Foundation

struct SourceTakeManifest: Codable, Equatable {
    struct SourceFile: Codable, Equatable {
        let role: String
        let path: String
    }

    let version: Int
    let updatedAt: Date
    let layout: String
    let outputResolution: String
    let outputVideoFormat: String
    let framesPerSecond: Int
    let enabledSources: [String]
    let sources: [SourceFile]
    let finalVideoPath: String?
}

final class OutputDirectoryAccess {
    private let url: URL
    private let shouldStopAccessing: Bool
    private var isStopped = false

    init(url: URL, usesSecurityScopedBookmark: Bool) {
        self.url = url
        shouldStopAccessing = usesSecurityScopedBookmark && url.startAccessingSecurityScopedResource()
    }

    deinit {
        stop()
    }

    func stop() {
        guard shouldStopAccessing, !isStopped else { return }
        url.stopAccessingSecurityScopedResource()
        isStopped = true
    }
}

struct TakeFileStore {
    static let minimumAvailableCapacityBytes: Int64 = 512 * 1024 * 1024

    func prepareOutputDirectory(settings: RecordingSettings) throws -> OutputDirectoryAccess {
        let access = OutputDirectoryAccess(
            url: settings.outputDirectory,
            usesSecurityScopedBookmark: settings.outputDirectoryBookmarkData != nil
        )

        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: settings.outputDirectory,
                withIntermediateDirectories: true
            )

            let scratchRoot = scratchRoot(for: settings)
            try fileManager.createDirectory(at: scratchRoot, withIntermediateDirectories: true)

            let probeURL = scratchRoot.appendingPathComponent(".write-test-\(UUID().uuidString)")
            try Data().write(to: probeURL, options: .atomic)
            try fileManager.removeItem(at: probeURL)
            let resourceValues = try settings.outputDirectory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
            )
            let fileSystemCapacity = Self.fileSystemAvailableCapacity(for: settings.outputDirectory)
            let capacity = Self.availableCapacityForRecording(
                importantUsageCapacity: resourceValues.volumeAvailableCapacityForImportantUsage,
                fallbackCapacity: resourceValues.volumeAvailableCapacity.map(Int64.init),
                fileSystemCapacity: fileSystemCapacity
            )
            if let capacity, capacity < Self.minimumAvailableCapacityBytes {
                throw RecorderError.outputDirectoryUnavailable(
                    "\(Self.formattedByteCount(capacity)) available; at least 512 MB required"
                )
            }
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
            throw RecorderError.outputDirectoryUnavailable(error.localizedDescription)
        }
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

    func createTake(settings: RecordingSettings, date: Date = Date()) throws -> RecordingTake {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

        let scratchRoot = scratchRoot(for: settings)
        let directory = scratchRoot
            .appendingPathComponent(formatter.string(from: date), isDirectory: true)
        let scratchDirectory = uniqueDirectory(directory)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        let take = RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: scratchDirectory.appendingPathComponent("screen.\(settings.outputVideoFormat.fileExtension)"),
            cameraURL: scratchDirectory.appendingPathComponent("camera.\(settings.outputVideoFormat.fileExtension)"),
            audioURL: scratchDirectory.appendingPathComponent("audio.\(settings.effectiveSourceAudioFormat.fileExtension)"),
            systemAudioURL: scratchDirectory.appendingPathComponent("system-audio.\(settings.effectiveSourceAudioFormat.fileExtension)"),
            transcriptURL: scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: finalVideoURL(
                slug: Self.defaultSlug(for: scratchDirectory),
                settings: settings,
                outputFormat: settings.outputVideoFormat
            ),
            outputVideoFormat: settings.outputVideoFormat,
            titleSlug: nil
        )
        if settings.savesSourceFiles {
            try writeSourceTakeManifest(for: take, settings: settings, finalVideoURL: nil)
        }
        return take
    }

    func cleanupIntermediateFiles(for take: RecordingTake, settings: RecordingSettings) {
        try? FileManager.default.removeItem(at: take.scratchDirectory)
        let scratchRoot = scratchRoot(for: settings)
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: scratchRoot.path),
           contents.isEmpty {
            try? FileManager.default.removeItem(at: scratchRoot)
        }
    }

    func writeSourceTakeManifest(
        for take: RecordingTake,
        settings: RecordingSettings,
        finalVideoURL: URL?
    ) throws {
        let manifest = SourceTakeManifest(
            version: 1,
            updatedAt: Date(),
            layout: settings.layout.rawValue,
            outputResolution: settings.outputResolution.rawValue,
            outputVideoFormat: settings.outputVideoFormat.rawValue,
            framesPerSecond: settings.framesPerSecond,
            enabledSources: settings.enabledSources
                .map(\.rawValue)
                .sorted(),
            sources: sourceFiles(for: take),
            finalVideoPath: finalVideoURL?.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: take.sourceManifestURL, options: .atomic)
    }

    func finalVideoURL(slug: String?, settings: RecordingSettings, outputFormat: OutputVideoFormat) -> URL {
        settings.outputDirectory
            .appendingPathComponent("\(slug ?? "recording")-final.\(outputFormat.fileExtension)")
    }

    func datedSlug(for take: RecordingTake, slug: String) -> String {
        datedSlug(for: take, slug: Optional(slug))
    }

    func datedSlug(for take: RecordingTake, slug: String?) -> String {
        let takeName = take.scratchDirectory.lastPathComponent
        let prefix = String(takeName.prefix(19))
        guard let slug, !slug.isEmpty else {
            return defaultSlug(for: take)
        }
        let slugPrefix = String(slug.prefix(19))
        guard Self.isTakeDatePrefix(prefix),
              !Self.isTakeDatePrefix(slugPrefix) else {
            return slug
        }
        return "\(prefix)-\(slug)"
    }

    func defaultSlug(for take: RecordingTake) -> String {
        Self.defaultSlug(for: take.scratchDirectory)
    }

    func uniqueFileURL(_ url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).\(pathExtension)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func scratchRoot(for settings: RecordingSettings) -> URL {
        settings.outputDirectory.appendingPathComponent("BlitzRecorder Source Takes", isDirectory: true)
    }

    private func sourceFiles(for take: RecordingTake) -> [SourceTakeManifest.SourceFile] {
        [
            ("screen", take.screenURL),
            ("camera", take.cameraURL),
            ("microphone", take.audioURL),
            ("systemAudio", take.systemAudioURL),
            ("transcript", take.transcriptURL)
        ].map { role, url in
            SourceTakeManifest.SourceFile(role: role, path: url.path)
        }
    }

    private static func defaultSlug(for scratchDirectory: URL) -> String {
        scratchDirectory.lastPathComponent
    }

    private static func isTakeDatePrefix(_ value: String) -> Bool {
        guard value.count == 19 else { return false }
        let characters = Array(value)
        let digitIndexes: Set<Int> = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        let dashIndexes: Set<Int> = [4, 7, 10, 13, 16]
        for index in characters.indices {
            if digitIndexes.contains(index), !characters[index].isNumber {
                return false
            }
            if dashIndexes.contains(index), characters[index] != "-" {
                return false
            }
        }
        return true
    }

    private func uniqueDirectory(_ url: URL) -> URL {
        var candidate = url
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}
