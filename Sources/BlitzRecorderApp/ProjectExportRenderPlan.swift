import Foundation

enum ProjectExportRenderPlan {
    static func settings(
        exportSettings: RecordingSettings,
        profile: ExportPerformanceProfile,
        outputLayout: CaptureLayout?,
        mutedAudioSources: Set<CaptureSource>,
        hiddenCaptureSources: Set<CaptureSource>
    ) -> RecordingSettings {
        var renderSettings = profile.applying(to: exportSettings)
        if let outputLayout {
            renderSettings.layout = outputLayout
        }
        if mutedAudioSources.contains(.microphone) {
            renderSettings.microphoneGain = 0
        }
        if mutedAudioSources.contains(.systemAudio) {
            renderSettings.systemAudioGain = 0
        }
        if !hiddenCaptureSources.isEmpty {
            renderSettings.enabledSources.subtract(hiddenCaptureSources)
        }
        return renderSettings
    }

    static func sceneEvents(
        _ events: [RecordingSceneEvent],
        hiddenCaptureSources: Set<CaptureSource>,
        profile: ExportPerformanceProfile
    ) -> [RecordingSceneEvent] {
        events.map { event in
            var scene = event.scene
            if !hiddenCaptureSources.isEmpty {
                scene.enabledSources.subtract(hiddenCaptureSources)
            }
            scene = profile.applying(to: scene)
            return RecordingSceneEvent(
                time: event.time,
                scene: scene,
                transition: event.transition
            )
        }
    }

    static func hiddenCaptureSources(_ hiddenVideoSources: Set<SceneLayerKind>) -> Set<CaptureSource> {
        Set(hiddenVideoSources.map(\.source))
    }

    struct RenderContext {
        let captureSettings: RecordingSettings
        let renderSettings: RecordingSettings
        let take: RecordingTake
        let originalSceneEvents: [RecordingSceneEvent]
        let renderSceneEvents: [RecordingSceneEvent]
    }

    static func context(
        request: ProjectExportRequest,
        captureSettings: RecordingSettings,
        exportSettings: RecordingSettings,
        take: RecordingTake,
        originalSceneEvents: [RecordingSceneEvent],
        outputProject: RecordingProject,
        outputSceneEvents: [RecordingSceneEvent]
    ) -> RenderContext {
        let hiddenCaptureSources = hiddenCaptureSources(request.hiddenVideoSources)
        return RenderContext(
            captureSettings: captureSettings,
            renderSettings: settings(
                exportSettings: exportSettings,
                profile: request.performanceProfile,
                outputLayout: CaptureLayout(rawValue: outputProject.settings.layout),
                mutedAudioSources: request.mutedAudioSources,
                hiddenCaptureSources: hiddenCaptureSources
            ),
            take: take,
            originalSceneEvents: originalSceneEvents,
            renderSceneEvents: sceneEvents(
                outputSceneEvents,
                hiddenCaptureSources: hiddenCaptureSources,
                profile: request.performanceProfile
            )
        )
    }

    static func captureOutputFormat(
        project: RecordingProject,
        fallback: OutputVideoFormat
    ) -> OutputVideoFormat {
        OutputVideoFormat(rawValue: project.settings.outputVideoFormat) ?? fallback
    }

    static func savedOutput(url: URL, take: RecordingTake) -> SavedRecordingOutput {
        SavedRecordingOutput(
            url: url,
            sourceDirectory: take.scratchDirectory,
            warning: nil
        )
    }

    static func exportRecord(
        url: URL,
        request: ProjectExportRequest,
        renderSettings: RecordingSettings,
        fileSizeBytes: Int64?
    ) -> RecordingProject.ExportRecord {
        let dimensions = renderSettings.outputResolution.dimensions(for: renderSettings.layout)
        return RecordingProject.ExportRecord(
            id: UUID(),
            createdAt: Date(),
            path: url.path,
            format: request.outputFormat.rawValue,
            resolution: renderSettings.outputResolution.rawValue,
            framesPerSecond: renderSettings.framesPerSecond,
            quality: request.performanceProfile.videoQuality.rawValue,
            fileSizeBytes: fileSizeBytes,
            layout: renderSettings.layout.rawValue,
            width: dimensions.width,
            height: dimensions.height
        )
    }
}
