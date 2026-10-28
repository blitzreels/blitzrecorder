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

        var take = RecordingTake(
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
        take.cameraAngleFiles = NumberedSourceTracks.cameraAngles.files(
            directory: scratchDirectory,
            count: settings.recordedExtraCameraAngleIDs.count,
            fileExtension: settings.sourceVideoFormat.fileExtension
        )
        let extraMicrophoneCount = settings.recordedExtraMicrophoneIDs.count
        take.microphoneTrackFiles = NumberedSourceTracks.microphones.files(
            directory: scratchDirectory,
            count: extraMicrophoneCount == 0 ? 0 : extraMicrophoneCount + 1,
            fileExtension: settings.effectiveSourceAudioFormat.fileExtension
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
        chapters: [RecordingProject.ChapterSnapshot]? = nil,
        editorTimeline: RecordingProject.TimelineSnapshot? = nil,
        editorState: RecordingProject.EditorStateSnapshot? = nil,
        exportRecord: RecordingProject.ExportRecord? = nil,
        timelineEdits: RecordingProject.TimelineEditsSnapshot? = nil
    ) throws {
        let edits = ProjectEdits(
            take: take, settings: settings, sceneEvents: sceneEvents, finalVideoURL: finalVideoURL, chapters: chapters,
            editorTimeline: editorTimeline, editorState: editorState, exportRecord: exportRecord, timelineEdits: timelineEdits
        )
        if let draft = Self.draft, draft.matches(take.projectURL) {
            // Editor changes are worked out on the copy the editor shows; `ProjectSaveQueue` writes them.
            draft.project = recordingProject(.init(edits: edits, existing: draft.project, sources: draft.project.sources))
            return
        }
        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        let projectURL = take.projectURL
        // A project that exists but can't be read is never replaced: that would silently drop its edits and exports.
        let existingProject = FileManager.default.fileExists(atPath: projectURL.path)
            ? try loadRecordingProject(at: projectURL)
            : nil
        let project = recordingProject(.init(edits: edits, existing: existingProject, sources: projectSourceFiles(for: take)))
        let data = try Self.projectEncoder().encode(project)
        try data.write(to: projectURL, options: .atomic)
        if let existingProject, existingProject.editRevision != project.editRevision {
            Self.postProjectEdited(project)
        }
        try upsertProjectHistory(project, settings: settings)
    }

    private struct ProjectEdits {
        let take: RecordingTake
        let settings: RecordingSettings
        let sceneEvents: [RecordingSceneEvent]
        let finalVideoURL: URL?
        let chapters: [RecordingProject.ChapterSnapshot]?
        let editorTimeline: RecordingProject.TimelineSnapshot?
        let editorState: RecordingProject.EditorStateSnapshot?
        let exportRecord: RecordingProject.ExportRecord?
        let timelineEdits: RecordingProject.TimelineEditsSnapshot?
    }

    private struct ProjectBuild {
        let edits: ProjectEdits
        let existing: RecordingProject?
        let sources: [RecordingProject.SourceFile]
    }

    /// The project these edits make. Fields the caller leaves nil keep what `existing` has.
    private func recordingProject(_ build: ProjectBuild) -> RecordingProject {
        let edits = build.edits
        let take = edits.take
        let existingProject = build.existing
        let now = Date()
        var exports = existingProject?.exports ?? []
        if let exportRecord = edits.exportRecord {
            exports = exports.upserting(exportRecord)
        }
        var project = RecordingProject(
            version: 1,
            id: existingProject?.id ?? UUID(),
            createdAt: projectCreatedAt(for: take, fallback: now),
            updatedAt: now,
            title: take.titleSlug ?? Self.defaultSlug(for: take.scratchDirectory),
            projectPath: take.projectURL.path,
            takeDirectoryPath: take.scratchDirectory.path,
            finalVideoPath: edits.finalVideoURL?.path,
            settings: RecordingProject.SettingsSnapshot(edits.settings),
            sources: build.sources,
            sceneEvents: edits.sceneEvents.map(RecordingProject.SceneEventSnapshot.init),
            chapters: edits.chapters ?? existingProject?.chapters ?? [],
            editorTimeline: edits.editorTimeline ?? existingProject?.editorTimeline ?? .empty,
            editorState: edits.editorState ?? existingProject?.editorState ?? .empty,
            exports: exports,
            timelineTrimOffsetSeconds: max(0, take.timelineTrimOffset.seconds),
            sourceTimelineOffsetSeconds: Dictionary(uniqueKeysWithValues: take.sourceTimelineOffsets.map {
                ($0.key.rawValue, max(0, $0.value.seconds))
            }),
            timelineEdits: edits.timelineEdits ?? existingProject?.timelineEdits ?? .empty,
            analysis: existingProject?.analysis ?? .empty
        )
        if let existingProject {
            project.editRevision = existingProject.editRevision + (project.hasSameEdits(as: existingProject) ? 0 : 1)
        }
        return project
    }

    /// Writes an editor change worked out in draft mode, on the save queue. It lands only on the revision it was
    /// made on, or when the file already holds exactly these edits (a rename or export wrote them meanwhile).
    func saveStagedProject(_ save: ProjectSaveQueue.Save) throws -> RecordingProject {
        Self.projectWriteLock.lock()
        defer { Self.projectWriteLock.unlock() }
        let current = try loadRecordingProject(at: save.projectURL)
        let alreadyHoldsEdits = current.editRevision == save.project.editRevision && current.hasSameEdits(as: save.project)
        guard current.editRevision == save.baseRevision || alreadyHoldsEdits else {
            throw ProjectEditConflict(current: current)
        }
        let project = save.project.keepingSavedMetadata(from: current)
        try Self.projectEncoder().encode(project).write(to: save.projectURL, options: .atomic)
        if current.editRevision != project.editRevision { Self.postProjectEdited(project) }
        do {
            try upsertProjectHistory(project, settings: save.settings)
        } catch {
            // The edit is saved; the list repairs itself from the take folders on the next load.
            Self.logLibraryIndexFailure(error)
        }
        return project
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
        ] + (take.cameraAngleFiles + take.microphoneTrackFiles).map { ($0.role, $0.url) }
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
