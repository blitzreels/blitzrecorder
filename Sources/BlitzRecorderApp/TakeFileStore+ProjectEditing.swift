import CoreGraphics
import CoreMedia
import Foundation

extension TakeFileStore {
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
            }),
            sourceReferences: project.sources.filter { $0.bookmarkData != nil }
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

        let requestedVideoSources = correction.videoSources
        let availableVideoSources = availableRecordedVideoSources(in: project)
        guard requestedVideoSources.isSubset(of: availableVideoSources) else {
            throw RecorderError.mediaWriteFailed("That scene correction requires a source file that is missing from this project.")
        }
        let layout = recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: project.outputVideoFormat(fallback: baseSettings.outputVideoFormat)
        ).layout
        let correctedScene = sceneEvents[eventIndex].scene.corrected(correction, layout: layout)
        sceneEvents[eventIndex] = RecordingSceneEvent(
            time: sceneEvents[eventIndex].time,
            scene: correctedScene,
            transition: sceneEvents[eventIndex].transition
        )
        return try rewriteProject(.init(project: project, projectURL: projectURL, baseSettings: baseSettings,
                                        sceneEvents: sceneEvents))
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

        var scene = sceneEvents[eventIndex].scene
        mutate(&scene)
        sceneEvents[eventIndex] = RecordingSceneEvent(
            time: sceneEvents[eventIndex].time,
            scene: scene,
            transition: sceneEvents[eventIndex].transition
        )
        return try rewriteProject(.init(project: project, projectURL: projectURL, baseSettings: baseSettings,
                                        sceneEvents: sceneEvents))
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

        let sourceIndex = sceneEvents.lastIndex { $0.time < time } ?? 0
        let sourceEvent = sceneEvents[sourceIndex]
        sceneEvents.append(RecordingSceneEvent(time: time, scene: sourceEvent.scene, transition: .cut))
        sceneEvents.sort { $0.time < $1.time }
        return try rewriteProject(.init(project: project, projectURL: projectURL, baseSettings: baseSettings,
                                        sceneEvents: sceneEvents))
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
        return try rewriteProject(.init(project: project, projectURL: projectURL, baseSettings: baseSettings,
                                        sceneEvents: sceneEvents))
    }

    func restoreProjectSceneTimeline(
        _ request: RecordingProjectSceneRestoreRequest
    ) throws -> RecordingProject {
        let currentProject = try loadRecordingProject(at: request.projectURL)
        guard currentProject.id == request.snapshot.id else {
            throw RecorderError.mediaWriteFailed("The undo history belongs to another project.")
        }
        let sceneEvents = sceneEvents(from: request.snapshot)
        guard !sceneEvents.isEmpty else {
            throw RecorderError.mediaWriteFailed("The undo state has no scene timeline.")
        }
        return try rewriteProject(.init(
            project: currentProject,
            projectURL: request.projectURL,
            baseSettings: request.baseSettings,
            sceneEvents: sceneEvents,
            editorState: request.snapshot.editorState,
            timelineEdits: request.snapshot.timelineEdits
        ))
    }

    func updateProjectTimelineEdits(
        _ request: RecordingProjectTimelineEditsUpdateRequest
    ) throws -> RecordingProject {
        let project = try loadRecordingProject(at: request.projectURL)
        return try rewriteProject(.init(
            project: project,
            projectURL: request.projectURL,
            baseSettings: request.baseSettings,
            editorState: project.editorState,
            timelineEdits: RecordingProject.TimelineEditsSnapshot(request.edits)
        ))
    }

    func updateProjectEditorState(
        _ request: RecordingProjectEditorStateUpdateRequest
    ) throws -> RecordingProject {
        try rewriteProject(.init(
            project: loadRecordingProject(at: request.projectURL),
            projectURL: request.projectURL,
            baseSettings: request.baseSettings,
            editorState: request.editorState
        ))
    }

    private struct ProjectRewrite {
        let project: RecordingProject
        let projectURL: URL
        let baseSettings: RecordingSettings
        var sceneEvents: [RecordingSceneEvent]?
        var editorState: RecordingProject.EditorStateSnapshot?
        var timelineEdits: RecordingProject.TimelineEditsSnapshot?
    }

    /// Fields left `nil` keep what the saved project already has.
    private func rewriteProject(_ rewrite: ProjectRewrite) throws -> RecordingProject {
        let project = rewrite.project
        let outputFormat = project.outputVideoFormat(fallback: rewrite.baseSettings.outputVideoFormat)
        var settings = recordingSettings(from: project, baseSettings: rewrite.baseSettings, outputFormat: outputFormat)
        if let editedSceneEvents = rewrite.sceneEvents {
            settings = settingsBySyncingEnabledVideoSources(settings, sceneEvents: editedSceneEvents)
        }
        let take = recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        try writeRecordingProject(
            for: take,
            settings: settings,
            sceneEvents: rewrite.sceneEvents ?? sceneEvents(from: project),
            finalVideoURL: project.finalVideoPath.map(URL.init(fileURLWithPath:)),
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: rewrite.editorState,
            timelineEdits: rewrite.timelineEdits
        )
        return try loadRecordingProject(at: rewrite.projectURL)
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
                  let captureSource = RecordingProject.captureSource(forPortableRole: source.role),
                  captureSource == .screen || captureSource == .camera else {
                return nil
            }
            return captureSource
        })
    }
}

private extension RecordingProject {
    func outputVideoFormat(fallback: OutputVideoFormat) -> OutputVideoFormat {
        OutputVideoFormat(rawValue: settings.outputVideoFormat) ?? fallback
    }
}
