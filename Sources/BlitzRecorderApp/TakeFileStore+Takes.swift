import CoreMedia
import Foundation

extension TakeFileStore {
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
        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        let now = Date()
        let projectURL = take.projectURL
        let existingProject = try? loadRecordingProject(at: projectURL)
        var exports = existingProject?.exports ?? []
        if let exportRecord {
            exports = exports.upserting(exportRecord)
        }
        var project = RecordingProject(
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
        if let existingProject {
            project.editRevision = existingProject.editRevision + (project.hasSameEdits(as: existingProject) ? 0 : 1)
        }

        let data = try Self.projectEncoder().encode(project)
        try data.write(to: projectURL, options: .atomic)
        if let existingProject, existingProject.editRevision != project.editRevision {
            NotificationCenter.default.post(
                name: .recordingProjectEdited,
                object: RecordingProjectEdited(projectPath: project.projectPath, editRevision: project.editRevision)
            )
        }
        try upsertProjectHistory(project, settings: settings)
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
            SourceTakeManifest.SourceFile(role: role, path: url.path,
                bookmarkData: take.sourceReferences.first { $0.role == role }?.bookmarkData)
        }
    }

    private func projectSourceFiles(for take: RecordingTake) -> [RecordingProject.SourceFile] {
        sourceRoleURLs(for: take).map { role, url in
            var source = RecordingProject.SourceFile(
                role: role,
                path: url.path,
                exists: FileManager.default.fileExists(atPath: url.path),
                bookmarkData: take.sourceReferences.first { $0.role == role }?.bookmarkData
            )
            source.resolveExternalReference()
            return source
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
}
