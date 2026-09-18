import CoreGraphics
import CoreMedia
import Foundation

struct TakeFileStore {
    private static let projectHistoryLock = NSRecursiveLock()
    static let minimumAvailableCapacityBytes: Int64 = 512 * 1024 * 1024

    func prepareOutputDirectory(settings: RecordingSettings) throws -> OutputDirectoryAccess {
        let access = OutputDirectoryAccess(
            url: settings.outputDirectory,
            usesSecurityScopedBookmark: settings.outputDirectoryBookmarkData != nil
        )
        guard access.hasSecurityScopedAccess else {
            access.stop()
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: settings.outputDirectory))
        }

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
            throw RecorderError.outputDirectoryUnavailable(Self.outputDirectoryFailureMessage(error, url: settings.outputDirectory))
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

    private static func permissionRecoveryMessage(for url: URL) -> String {
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
            screenURL: scratchDirectory.appendingPathComponent("screen.\(settings.sourceVideoFormat.fileExtension)"),
            cameraURL: scratchDirectory.appendingPathComponent("camera.\(settings.sourceVideoFormat.fileExtension)"),
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
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
        timelineEdits: RecordingProject.TimelineEditsSnapshot? = nil,
        analysis: RecordingProject.AnalysisSnapshot? = nil
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
            analysis: analysis ?? existingProject?.analysis ?? .empty
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: projectURL, options: .atomic)
        try upsertProjectHistory(project, settings: settings)
    }

    func loadProjectHistory(settings: RecordingSettings) -> RecordingProjectHistory {
        let url = projectHistoryURL(for: settings)
        guard let data = try? Data(contentsOf: url) else {
            return RecordingProjectHistory(version: 1, entries: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var history = try? decoder.decode(RecordingProjectHistory.self, from: data) else {
            return RecordingProjectHistory(version: 1, entries: [])
        }
        history.sortByRecordedDate()
        return history
    }

    func loadRecordingProject(at url: URL) throws -> RecordingProject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(RecordingProject.self, from: data)
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(renamedProject).write(
            to: request.projectURL,
            options: .atomic
        )
        try upsertProjectHistory(renamedProject, settings: request.settings)
        return renamedProject
    }

    @discardableResult
    func deleteProject(_ request: RecordingProjectDeletionRequest) throws -> RecordingProjectTrashReceipt? {
        let fileManager = FileManager.default
        let outputDirectoryAccess = OutputDirectoryAccess(
            url: request.settings.outputDirectory,
            usesSecurityScopedBookmark: request.settings.outputDirectoryBookmarkData != nil
        )
        guard outputDirectoryAccess.hasSecurityScopedAccess else {
            outputDirectoryAccess.stop()
            throw RecorderError.outputDirectoryUnavailable(
                Self.permissionRecoveryMessage(for: request.settings.outputDirectory)
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
        var history = loadProjectHistory(settings: request.settings)
        history.entries.removeAll {
            $0.id == request.project.id || $0.projectPath == request.project.projectPath
        }
        do {
            try writeProjectHistory(ProjectHistoryWriteRequest(history: history, settings: request.settings))
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
        let access = OutputDirectoryAccess(
            url: request.settings.outputDirectory,
            usesSecurityScopedBookmark: request.settings.outputDirectoryBookmarkData != nil
        )
        defer { access.stop() }
        guard access.hasSecurityScopedAccess else {
            throw RecorderError.outputDirectoryUnavailable(Self.permissionRecoveryMessage(for: request.settings.outputDirectory))
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
        let root = scratchRoot(for: request.settings).standardizedFileURL.resolvingSymlinksInPath()
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

    func recordingTake(
        from project: RecordingProject,
        settings: RecordingSettings,
        outputFormat: OutputVideoFormat
    ) -> RecordingTake {
        let scratchDirectory = URL(fileURLWithPath: project.takeDirectoryPath, isDirectory: true)
        let sourceURLByRole = Dictionary(uniqueKeysWithValues: project.sources.map { ($0.role, URL(fileURLWithPath: $0.path)) })
        return RecordingTake(
            scratchDirectory: scratchDirectory,
            screenURL: sourceURLByRole["screen"] ?? scratchDirectory.appendingPathComponent("screen.mov"),
            cameraURL: sourceURLByRole["camera"] ?? scratchDirectory.appendingPathComponent("camera.mov"),
            audioURL: sourceURLByRole["microphone"] ?? scratchDirectory.appendingPathComponent("audio.m4a"),
            systemAudioURL: sourceURLByRole["systemAudio"] ?? scratchDirectory.appendingPathComponent("system-audio.m4a"),
            transcriptURL: sourceURLByRole["transcript"] ?? scratchDirectory.appendingPathComponent("transcript.txt"),
            finalVideoURL: finalVideoURL(slug: project.title, settings: settings, outputFormat: outputFormat),
            outputVideoFormat: outputFormat,
            titleSlug: project.title,
            timelineTrimOffset: CMTime(
                seconds: max(0, project.timelineTrimOffsetSeconds),
                preferredTimescale: 600
            ),
            sourceTimelineOffsets: Dictionary(uniqueKeysWithValues: project.sourceTimelineOffsetSeconds.compactMap {
                key, seconds in
                guard let source = CaptureSource(rawValue: key) else { return nil }
                return (
                    source,
                    CMTime(seconds: max(0, seconds), preferredTimescale: 600)
                )
            })
        )
    }

    func recordingSettings(
        from project: RecordingProject,
        baseSettings: RecordingSettings,
        outputFormat: OutputVideoFormat
    ) -> RecordingSettings {
        var settings = baseSettings
        settings.voiceCleanup = project.edits.voiceCleanup
        settings.layout = CaptureLayout(rawValue: project.settings.layout) ?? settings.layout
        settings.outputResolution = OutputResolution(rawValue: project.settings.outputResolution) ?? settings.outputResolution
        settings.outputVideoFormat = outputFormat
        settings.framesPerSecond = RecordingSettings.supportedFrameRates.contains(project.settings.framesPerSecond)
            ? project.settings.framesPerSecond
            : settings.framesPerSecond
        settings.enabledSources = Set(project.settings.enabledSources.compactMap(CaptureSource.init(rawValue:)))
        settings.hiddenSources = Set(project.settings.hiddenSources.compactMap(CaptureSource.init(rawValue:)))
        settings.microphoneGain = CaptureValueClamps.gain(project.settings.microphoneGain ?? settings.microphoneGain)
        settings.systemAudioGain = CaptureValueClamps.gain(project.settings.systemAudioGain ?? settings.systemAudioGain)
        settings.canvasBackgroundStyle = CanvasBackgroundStyle(rawValue: project.settings.canvasBackgroundStyle) ?? settings.canvasBackgroundStyle
        settings.canvasBackgroundAnimated = project.settings.canvasBackgroundAnimated
        settings.canvasPadding = CGFloat(project.settings.canvasPadding)
        settings.screenCornerRadius = CGFloat(project.settings.screenCornerRadius ?? 0)
        settings.screenShadowEnabled = project.settings.screenShadowEnabled ?? false
        settings.screenContentMode = project.settings.screenContentMode
            .flatMap(CameraContentMode.init(rawValue:)) ?? settings.screenContentMode
        settings.cameraContentMode = CameraContentMode(rawValue: project.settings.cameraContentMode) ?? settings.cameraContentMode
        settings.cameraFramePadding = 0
        settings.cameraShadowEnabled = project.settings.cameraShadowEnabled
        settings.savesSourceFiles = true

        if let firstScene = sceneEvents(from: project).first?.scene {
            settings.sceneLayout = firstScene.sceneLayout
            settings.screenCrop = firstScene.screenSourceGeometry.normalizedCrop
            settings.usesPickedScreenContent = firstScene.screenSourceGeometry.usesPickedContent
            settings.selectedDisplayID = firstScene.screenSourceGeometry.selectedDisplayID
            settings.cameraCropAmount = firstScene.cameraCropAmount
            settings.cameraCropPosition = firstScene.cameraCropPosition
            settings.screenCornerRadius = firstScene.screenCornerRadius
            settings.screenShadowEnabled = firstScene.screenShadowEnabled
            settings.screenContentMode = firstScene.screenContentMode
        }
        return settings
    }

    func sceneEvents(from project: RecordingProject) -> [RecordingSceneEvent] {
        project.sceneEvents.compactMap { event in
            guard let scene = RecordingScene(snapshot: event.scene) else { return nil }
            return RecordingSceneEvent(
                time: event.time,
                scene: scene,
                transition: RecordingSceneTransition(snapshot: event.transition)
            )
        }
    }

    func updateProjectSceneEvent(
        at projectURL: URL,
        eventIndex: Int,
        correction: RecordingProjectSceneCorrection,
        baseSettings: RecordingSettings
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard sceneEvents.indices.contains(eventIndex) else {
            throw RecorderError.mediaWriteFailed("Scene event no longer exists in this project.")
        }

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        let requestedVideoSources = videoSources(for: correction)
        let availableVideoSources = availableRecordedVideoSources(in: project)
        guard requestedVideoSources.isSubset(of: availableVideoSources) else {
            throw RecorderError.mediaWriteFailed("That scene correction requires a source file that is missing from this project.")
        }
        let correctedScene = sceneEvents[eventIndex].scene.corrected(
            correction,
            layout: settings.layout
        )
        sceneEvents[eventIndex] = RecordingSceneEvent(
            time: sceneEvents[eventIndex].time,
            scene: correctedScene,
            transition: sceneEvents[eventIndex].transition
        )
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        baseSettings: RecordingSettings,
        mutate: (inout RecordingScene) -> Void
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard sceneEvents.indices.contains(eventIndex) else {
            throw RecorderError.mediaWriteFailed("Scene event no longer exists in this project.")
        }

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        var scene = sceneEvents[eventIndex].scene
        mutate(&scene)
        sceneEvents[eventIndex] = RecordingSceneEvent(
            time: sceneEvents[eventIndex].time,
            scene: scene,
            transition: sceneEvents[eventIndex].transition
        )
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func insertProjectSceneEvent(
        at projectURL: URL,
        time: Double,
        baseSettings: RecordingSettings
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard !sceneEvents.isEmpty else {
            throw RecorderError.mediaWriteFailed("This project has no scene timeline to split.")
        }
        guard time > 0.05 else {
            throw RecorderError.mediaWriteFailed("Move the playhead past the start before splitting.")
        }
        guard !sceneEvents.contains(where: { abs($0.time - time) < 0.05 }) else {
            throw RecorderError.mediaWriteFailed("A cut already exists at this playhead position.")
        }

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        let sourceIndex = sceneEvents.lastIndex { $0.time < time } ?? 0
        let sourceEvent = sceneEvents[sourceIndex]
        sceneEvents.append(RecordingSceneEvent(time: time, scene: sourceEvent.scene, transition: .cut))
        sceneEvents.sort { $0.time < $1.time }
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func removeProjectSceneEvent(
        at projectURL: URL,
        eventIndex: Int,
        baseSettings: RecordingSettings
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: projectURL)
        var sceneEvents = sceneEvents(from: project)
        guard sceneEvents.indices.contains(eventIndex), eventIndex > 0 else {
            throw RecorderError.mediaWriteFailed("Select a cut after the first segment to remove it.")
        }
        sceneEvents.remove(at: eventIndex)

        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)

        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline
        )
        return try loadRecordingProject(at: projectURL)
    }

    func restoreProjectSceneTimeline(
        _ request: RecordingProjectSceneRestoreRequest
    ) throws -> RecordingProject {
        let currentProject = try loadRecordingProject(at: request.projectURL)
        guard currentProject.id == request.snapshot.id else {
            throw RecorderError.mediaWriteFailed("The undo history belongs to another project.")
        }
        let outputFormat = OutputVideoFormat(rawValue: currentProject.settings.outputVideoFormat)
            ?? request.baseSettings.outputVideoFormat
        var settings = recordingSettings(
            from: currentProject,
            baseSettings: request.baseSettings,
            outputFormat: outputFormat
        )
        let sceneEvents = sceneEvents(from: request.snapshot)
        guard !sceneEvents.isEmpty else {
            throw RecorderError.mediaWriteFailed("The undo state has no scene timeline.")
        }
        settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: sceneEvents)
        let take = recordingTake(from: currentProject, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents,
            finalVideoURL: currentProject.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: currentProject.chapters,
            editorTimeline: currentProject.editorTimeline,
            editorState: request.snapshot.editorState,
            timelineEdits: request.snapshot.timelineEdits
        )
        return try loadRecordingProject(at: request.projectURL)
    }

    func updateProjectTimelineEdits(
        _ request: RecordingProjectTimelineEditsUpdateRequest
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: request.projectURL)
        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
            ?? request.baseSettings.outputVideoFormat
        let settings = recordingSettings(
            from: project,
            baseSettings: request.baseSettings,
            outputFormat: outputFormat
        )
        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents(from: project),
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: project.editorState,
            timelineEdits: RecordingProject.TimelineEditsSnapshot(request.edits)
        )
        return try loadRecordingProject(at: request.projectURL)
    }

    func updateProjectAnalysis(
        _ request: RecordingProjectAnalysisUpdateRequest
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: request.projectURL)
        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
            ?? request.baseSettings.outputVideoFormat
        let settings = recordingSettings(
            from: project,
            baseSettings: request.baseSettings,
            outputFormat: outputFormat
        )
        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents(from: project),
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: project.editorState,
            timelineEdits: project.timelineEdits,
            analysis: request.analysis
        )
        return try loadRecordingProject(at: request.projectURL)
    }

    func updateProjectEditorState(
        _ request: RecordingProjectEditorStateUpdateRequest
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: request.projectURL)
        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
            ?? request.baseSettings.outputVideoFormat
        let settings = recordingSettings(
            from: project,
            baseSettings: request.baseSettings,
            outputFormat: outputFormat
        )
        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: sceneEvents(from: project),
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: request.editorState
        )
        return try loadRecordingProject(at: request.projectURL)
    }

    private func settingsBySyncingEnabledVideoSources(
        _ settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> RecordingSettings {
        let videoSources: Set<CaptureSource> = [.screen, .camera]
        let editedVideoSources = Set(sceneEvents.flatMap(\.scene.enabledSources).filter(videoSources.contains))
        guard !editedVideoSources.isEmpty else { return settings }

        var updated = settings
        let audioSources = updated.enabledSources.subtracting(videoSources)
        updated.enabledSources = audioSources.union(editedVideoSources)
        updated.hiddenSources.subtract(videoSources)
        return updated
    }

    private func availableRecordedVideoSources(in project: RecordingProject) -> Set<CaptureSource> {
        Set(project.sources.compactMap { source in
            guard FileManager.default.fileExists(atPath: source.path),
                  let captureSource = captureSource(forProjectRole: source.role),
                  captureSource == .screen || captureSource == .camera else {
                return nil
            }
            return captureSource
        })
    }

    private func captureSource(forProjectRole role: String) -> CaptureSource? {
        switch role {
        case "screen":
            return .screen
        case "camera":
            return .camera
        case "microphone":
            return .microphone
        case "systemAudio":
            return .systemAudio
        default:
            return CaptureSource(rawValue: role)
        }
    }

    private func videoSources(for correction: RecordingProjectSceneCorrection) -> Set<CaptureSource> {
        switch correction {
        case .screenOnly:
            return [.screen]
        case .cameraOnly:
            return [.camera]
        case .screenAndCamera:
            return [.screen, .camera]
        }
    }

    func projectHistoryURL(for settings: RecordingSettings) -> URL {
        settings.outputDirectory
            .appendingPathComponent("BlitzRecorder Projects", isDirectory: true)
            .appendingPathComponent("projects.json")
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

    private func projectID(for take: RecordingTake, projectURL: URL) -> UUID {
        if let data = try? Data(contentsOf: projectURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let existing = try? decoder.decode(RecordingProject.self, from: data) {
                return existing.id
            }
        }
        return UUID()
    }

    private func projectCreatedAt(for take: RecordingTake, fallback: Date) -> Date {
        let prefix = String(take.scratchDirectory.lastPathComponent.prefix(19))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.date(from: prefix) ?? fallback
    }

    private func upsertProjectHistory(_ project: RecordingProject, settings: RecordingSettings) throws {
        Self.projectHistoryLock.lock()
        defer { Self.projectHistoryLock.unlock() }
        var history = loadProjectHistory(settings: settings)
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

    private func writeProjectHistory(_ request: ProjectHistoryWriteRequest) throws {
        let historyURL = projectHistoryURL(for: request.settings)
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request.history)
        try data.write(to: historyURL, options: .atomic)
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

    private func projectSourceFiles(for take: RecordingTake) -> [RecordingProject.SourceFile] {
        [
            ("screen", take.screenURL),
            ("camera", take.cameraURL),
            ("microphone", take.audioURL),
            ("systemAudio", take.systemAudioURL),
            ("transcript", take.transcriptURL)
        ].map { role, url in
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
}
