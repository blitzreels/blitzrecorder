import CoreGraphics
import CoreMedia
import Foundation

struct TakeFileStore {
    private static let projectHistoryLock = NSRecursiveLock()

    struct TakeCreationRequest {
        let settings: RecordingSettings
        let date: Date
        let title: String?
    }

    func createTake(settings: RecordingSettings, date: Date = Date()) throws -> RecordingTake {
        try createTake(.init(settings: settings, date: date, title: nil))
    }

    func createTake(_ request: TakeCreationRequest) throws -> RecordingTake {
        let settings = request.settings
        let date = request.date
        let formatter = Self.takeDateFormatter()

        let scratchRoot = scratchRoot(for: settings)
        let directory = scratchRoot
            .appendingPathComponent(formatter.string(from: date), isDirectory: true)
        let scratchDirectory = uniqueDirectory(directory)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)

        let take = RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: scratchDirectory.appendingPathComponent("screen.\(settings.sourceVideoFormat.fileExtension)"),
            cameraURL: scratchDirectory.appendingPathComponent("camera.\(settings.sourceVideoFormat.fileExtension)"),
            audioURL: scratchDirectory.appendingPathComponent("audio.\(settings.effectiveSourceAudioFormat.fileExtension)"),
            systemAudioURL: scratchDirectory.appendingPathComponent("system-audio.\(settings.effectiveSourceAudioFormat.fileExtension)"),
            transcriptURL: scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: finalVideoURL(
                slug: request.title.map(ProjectExportFilename.slug(from:)) ?? Self.defaultSlug(for: scratchDirectory),
                settings: settings,
                outputFormat: settings.outputVideoFormat
            ),
            outputVideoFormat: settings.outputVideoFormat,
            titleSlug: request.title
        )
        if settings.savesSourceFiles {
            try writeSourceTakeManifest(for: take, settings: settings, finalVideoURL: nil)
            try writeRecordingProject(
                for: take,
                settings: settings,
                sceneEvents: [RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))],
                finalVideoURL: nil
            )
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

        let data = try Self.projectEncoder().encode(manifest)
        try data.write(to: take.sourceManifestURL, options: .atomic)
    }

    func writeRecordingProject(
        for take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        finalVideoURL: URL?,
        chapters: [RecordingProject.ChapterSnapshot] = [],
        editorTimeline: RecordingProject.TimelineSnapshot = .empty,
        editorState: RecordingProject.EditorStateSnapshot? = nil,
        exportRecord: RecordingProject.ExportRecord? = nil,
        timelineEdits: RecordingProject.TimelineEditsSnapshot? = nil
    ) throws {
        let now = Date()
        let projectURL = take.projectURL
        let existingProject = try? loadRecordingProject(at: projectURL)
        var exports = existingProject?.exports ?? []
        if let exportRecord {
            exports.removeAll { $0.path == exportRecord.path }
            exports.append(exportRecord)
            exports.sort { $0.createdAt < $1.createdAt }
        }
        let project = RecordingProject(
            version: 1,
            id: projectID(for: take, projectURL: projectURL),
            createdAt: projectCreatedAt(for: take, fallback: now),
            updatedAt: now,
            title: take.titleSlug ?? Self.defaultSlug(for: take.scratchDirectory),
            projectPath: projectURL.path,
            takeDirectoryPath: take.scratchDirectory.path,
            finalVideoPath: finalVideoURL?.path,
            settings: RecordingProject.SettingsSnapshot(settings),
            sources: projectSourceFiles(for: take),
            sceneEvents: sceneEvents.map(RecordingProject.SceneEventSnapshot.init),
            chapters: chapters,
            editorTimeline: editorTimeline,
            editorState: editorState ?? existingProject?.editorState ?? .empty,
            exports: exports,
            timelineTrimOffsetSeconds: max(0, take.timelineTrimOffset.seconds),
            sourceTimelineOffsetSeconds: Dictionary(uniqueKeysWithValues: take.sourceTimelineOffsets.map {
                ($0.key.rawValue, max(0, $0.value.seconds))
            }),
            timelineEdits: timelineEdits ?? existingProject?.timelineEdits ?? .empty,
            analysis: existingProject?.analysis ?? .empty
        )

        let data = try Self.projectEncoder().encode(project)
        try data.write(to: projectURL, options: .atomic)
        try upsertProjectHistory(project, settings: settings)
    }

    func loadProjectHistory(settings: RecordingSettings) -> RecordingProjectHistory {
        var entries: [RecordingProjectHistory.Entry] = []
        let roots = Set(settings.projectLibraries.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() })
        for location in settings.projectLibraries {
            var librarySettings = settings
            librarySettings.projectLibrary = location
            let access = OutputDirectoryAccess(locations: [location])
            defer { access.stop() }
            guard access.hasSecurityScopedAccess else { continue }
            let root = location.url.standardizedFileURL.resolvingSymlinksInPath()
            entries += loadLocalProjectHistory(settings: librarySettings).entries.filter {
                let owner = URL(fileURLWithPath: $0.takeDirectoryPath).deletingLastPathComponent().deletingLastPathComponent()
                    .standardizedFileURL.resolvingSymlinksInPath()
                return owner == root || !roots.contains(owner)
            }
        }
        entries.sort { $0.updatedAt > $1.updatedAt }
        var ids: Set<UUID> = []
        var paths: Set<String> = []
        var history = RecordingProjectHistory(version: 1, entries: entries.filter {
            let path = URL(fileURLWithPath: $0.projectPath).standardizedFileURL.path
            guard !ids.contains($0.id), !paths.contains(path) else { return false }
            ids.insert($0.id)
            paths.insert(path)
            return true
        })
        history.sortByRecordedDate()
        return history
    }

    private func loadLocalProjectHistory(settings: RecordingSettings) -> RecordingProjectHistory {
        let url = projectHistoryURL(for: settings)
        guard let data = try? Data(contentsOf: url) else {
            return RecordingProjectHistory(version: 1, entries: [])
        }
        guard var history = try? Self.projectDecoder().decode(RecordingProjectHistory.self, from: data) else {
            return RecordingProjectHistory(version: 1, entries: [])
        }
        history.sortByRecordedDate()
        return history
    }

    func loadRecordingProject(at url: URL) throws -> RecordingProject {
        let data = try Data(contentsOf: url)
        do {
            return try Self.projectDecoder().decode(RecordingProject.self, from: data)
        } catch {
            return try RecordingProject.importedPortable(from: data, projectURL: url)
        }
    }

    func renameProject(
        _ request: RecordingProjectRenameRequest
    ) throws -> RecordingProject {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw RecorderError.mediaWriteFailed("Enter a recording title.")
        }

        let project = try loadRecordingProject(at: request.projectURL)
        let renamedProject = RecordingProject(
            version: project.version,
            id: project.id,
            createdAt: project.createdAt,
            updatedAt: Date(),
            title: title,
            projectPath: project.projectPath,
            takeDirectoryPath: project.takeDirectoryPath,
            finalVideoPath: project.finalVideoPath,
            settings: project.settings,
            sources: project.sources,
            sceneEvents: project.sceneEvents,
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: project.editorState,
            exports: project.exports,
            timelineTrimOffsetSeconds: project.timelineTrimOffsetSeconds,
            sourceTimelineOffsetSeconds: project.sourceTimelineOffsetSeconds,
            timelineEdits: project.timelineEdits,
            analysis: project.analysis
        )

        try Self.projectEncoder().encode(renamedProject).write(
            to: request.projectURL,
            options: .atomic
        )
        try upsertProjectHistory(renamedProject, settings: request.settings)
        return renamedProject
    }

    struct CompletedExportRequest {
        let projectURL: URL
        let record: RecordingProject.ExportRecord
        let settings: RecordingSettings
    }

    func recordCompletedExport(_ request: CompletedExportRequest) throws {
        let project = try loadRecordingProject(at: request.projectURL)
        var exports = project.exports.filter { $0.path != request.record.path }
        exports.append(request.record)
        exports.sort { $0.createdAt < $1.createdAt }
        let updated = RecordingProject(
            version: project.version, id: project.id, createdAt: project.createdAt, updatedAt: Date(),
            title: project.title, projectPath: project.projectPath, takeDirectoryPath: project.takeDirectoryPath,
            finalVideoPath: request.record.path, settings: project.settings, sources: project.sources,
            sceneEvents: project.sceneEvents, chapters: project.chapters, editorTimeline: project.editorTimeline,
            editorState: project.editorState, exports: exports,
            timelineTrimOffsetSeconds: project.timelineTrimOffsetSeconds,
            sourceTimelineOffsetSeconds: project.sourceTimelineOffsetSeconds,
            timelineEdits: project.timelineEdits, analysis: project.analysis
        )
        try Self.projectEncoder().encode(updated).write(to: request.projectURL, options: .atomic)
        try upsertProjectHistory(updated, settings: request.settings)
    }

    @discardableResult
    func deleteProject(_ request: RecordingProjectDeletionRequest) throws -> RecordingProjectTrashReceipt? {
        let fileManager = FileManager.default
        let librarySettings = projectLibrarySettings(.init(takePath: request.project.takeDirectoryPath, settings: request.settings))
        let outputDirectoryAccess = OutputDirectoryAccess(locations: [librarySettings.sourceStorage])
        guard outputDirectoryAccess.hasSecurityScopedAccess else {
            outputDirectoryAccess.stop()
            throw RecorderError.outputDirectoryUnavailable(
                Self.permissionRecoveryMessage(for: librarySettings.sourceStorage.url)
            )
        }
        defer {
            outputDirectoryAccess.stop()
        }

        let projectDirectory = URL(
            fileURLWithPath: request.project.takeDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        try validateProjectDeletionTarget(request)

        var receipt: RecordingProjectTrashReceipt?
        if fileManager.fileExists(atPath: projectDirectory.path) {
            switch request.disposition {
            case .trash:
                var trashedURL: NSURL?
                try fileManager.trashItem(at: projectDirectory, resultingItemURL: &trashedURL)
                if let trashedURL {
                    receipt = RecordingProjectTrashReceipt(project: request.project, trashedDirectory: trashedURL as URL)
                }
            case .permanent:
                try fileManager.removeItem(at: projectDirectory)
            }
        }

        Self.projectHistoryLock.lock()
        defer { Self.projectHistoryLock.unlock() }
        var history = loadLocalProjectHistory(settings: librarySettings)
        history.entries.removeAll {
            $0.id == request.project.id || $0.projectPath == request.project.projectPath
        }
        do {
            try writeProjectHistory(ProjectHistoryWriteRequest(history: history, settings: librarySettings))
        } catch {
            if let receipt {
                try fileManager.moveItem(at: receipt.trashedDirectory, to: projectDirectory)
            }
            throw error
        }
        return receipt
    }

    func restoreProjectFromTrash(_ request: RecordingProjectRestorationRequest) throws {
        let receipt = request.receipt
        let fileManager = FileManager.default
        let librarySettings = projectLibrarySettings(.init(takePath: receipt.project.takeDirectoryPath, settings: request.settings))
        let access = OutputDirectoryAccess(locations: [librarySettings.sourceStorage])
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: librarySettings.sourceStorage.url))
        }
        try validateProjectDeletionTarget(.init(project: receipt.project, settings: request.settings, disposition: .trash))
        let original = URL(fileURLWithPath: receipt.project.takeDirectoryPath, isDirectory: true)
        guard !fileManager.fileExists(atPath: original.path) else {
            throw RecorderError.mediaWriteFailed("A folder already exists for \"\(receipt.project.displayTitle)\". Nothing was replaced.")
        }
        let project = try loadRecordingProject(at: receipt.trashedDirectory.appendingPathComponent("project.blitzrecorder.json"))
        guard project.id == receipt.project.id else {
            throw RecorderError.mediaWriteFailed("The project in Trash no longer matches this recording.")
        }
        try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: receipt.trashedDirectory, to: original)
        do {
            try upsertProjectHistory(project, settings: request.settings)
        } catch {
            try fileManager.moveItem(at: original, to: receipt.trashedDirectory)
            throw error
        }
    }

    private func validateProjectDeletionTarget(_ request: RecordingProjectDeletionRequest) throws {
        let directory = URL(fileURLWithPath: request.project.takeDirectoryPath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let librarySettings = projectLibrarySettings(.init(takePath: request.project.takeDirectoryPath, settings: request.settings))
        let root = scratchRoot(for: librarySettings).standardizedFileURL.resolvingSymlinksInPath()
        let metadata = URL(fileURLWithPath: request.project.projectPath).standardizedFileURL.resolvingSymlinksInPath()
        guard directory.deletingLastPathComponent() == root,
            metadata.deletingLastPathComponent() == directory,
            metadata.lastPathComponent == "project.blitzrecorder.json"
        else {
            throw RecorderError.mediaWriteFailed("This project is outside the BlitzRecorder source projects folder.")
        }
        if FileManager.default.fileExists(atPath: metadata.path) {
            guard try loadRecordingProject(at: metadata).id == request.project.id else {
                throw RecorderError.mediaWriteFailed("The project folder belongs to a different recording.")
            }
        }
    }

    func projectHistoryURL(for settings: RecordingSettings) -> URL {
        settings.sourceStorage.url
            .appendingPathComponent("BlitzRecorder Projects", isDirectory: true)
            .appendingPathComponent("projects.json")
    }

    func finalVideoURL(slug: String?, settings: RecordingSettings, outputFormat: OutputVideoFormat) -> URL {
        settings.outputDirectory
            .appendingPathComponent("\(slug ?? "recording")-final.\(outputFormat.fileExtension)")
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

    func scratchRoot(for settings: RecordingSettings) -> URL {
        settings.sourceStorage.url.appendingPathComponent("BlitzRecorder Source Takes", isDirectory: true)
    }

    private func projectID(for take: RecordingTake, projectURL: URL) -> UUID {
        if let data = try? Data(contentsOf: projectURL) {
            if let existing = try? Self.projectDecoder().decode(RecordingProject.self, from: data) {
                return existing.id
            }
        }
        return UUID()
    }

    private func projectCreatedAt(for take: RecordingTake, fallback: Date) -> Date {
        let prefix = String(take.scratchDirectory.lastPathComponent.prefix(19))
        return Self.takeDateFormatter().date(from: prefix) ?? fallback
    }

    private func upsertProjectHistory(_ project: RecordingProject, settings: RecordingSettings) throws {
        Self.projectHistoryLock.lock()
        defer { Self.projectHistoryLock.unlock() }
        let settings = projectLibrarySettings(.init(takePath: project.takeDirectoryPath, settings: settings))
        let access = OutputDirectoryAccess(locations: [settings.sourceStorage])
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: settings.sourceStorage.url))
        }
        var history = loadLocalProjectHistory(settings: settings)
        history.entries.removeAll { $0.id == project.id || $0.projectPath == project.projectPath }
        history.entries.insert(
            RecordingProjectHistory.Entry(
                id: project.id,
                title: project.title,
                projectPath: project.projectPath,
                takeDirectoryPath: project.takeDirectoryPath,
                finalVideoPath: project.finalVideoPath,
                createdAt: project.createdAt,
                updatedAt: project.updatedAt,
                exports: project.exports
            ),
            at: 0
        )
        history.sortByRecordedDate()
        try writeProjectHistory(ProjectHistoryWriteRequest(
            history: history,
            settings: settings
        ))
    }

    private struct ProjectLibrarySettingsRequest {
        let takePath: String
        let settings: RecordingSettings
    }

    private func projectLibrarySettings(_ request: ProjectLibrarySettingsRequest) -> RecordingSettings {
        let root = URL(fileURLWithPath: request.takePath).deletingLastPathComponent().deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        var settings = request.settings
        if let location = settings.projectLibraries.first(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == root }) {
            settings.projectLibrary = location
        }
        return settings
    }

    private func writeProjectHistory(_ request: ProjectHistoryWriteRequest) throws {
        let historyURL = projectHistoryURL(for: request.settings)
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.projectEncoder().encode(request.history)
        try data.write(to: historyURL, options: .atomic)
    }

    private func sourceRoleURLs(for take: RecordingTake) -> [(role: String, url: URL)] {
        [
            ("screen", take.screenURL),
            ("camera", take.cameraURL),
            ("microphone", take.audioURL),
            ("systemAudio", take.systemAudioURL),
            ("transcript", take.transcriptURL)
        ]
    }

    private func sourceFiles(for take: RecordingTake) -> [SourceTakeManifest.SourceFile] {
        sourceRoleURLs(for: take).map { role, url in
            SourceTakeManifest.SourceFile(role: role, path: url.path)
        }
    }

    private func projectSourceFiles(for take: RecordingTake) -> [RecordingProject.SourceFile] {
        sourceRoleURLs(for: take).map { role, url in
            RecordingProject.SourceFile(
                role: role,
                path: url.path,
                exists: FileManager.default.fileExists(atPath: url.path)
            )
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

    private static func takeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }

    private static func projectEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func projectDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
