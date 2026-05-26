import Foundation

enum TakeFinalizationAction: Equatable {
    case recoverNoVideo(reason: String)
    case saveTransparentCameraOnly
    case exportFinalVideo
}

struct TakeFinalizationPlan: Equatable {
    let action: TakeFinalizationAction

    init(
        take: RecordingTake,
        settings: RecordingSettings,
        captureSummary: CaptureSourceRunSummary,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        if Self.shouldSaveTransparentCameraOnly(take: take, settings: settings, fileExists: fileExists) {
            action = .saveTransparentCameraOnly
        } else if !captureSummary.hasVideoMedia {
            action = .recoverNoVideo(reason: "No video frames captured")
        } else {
            action = .exportFinalVideo
        }
    }

    private static func shouldSaveTransparentCameraOnly(
        take: RecordingTake,
        settings: RecordingSettings,
        fileExists: (URL) -> Bool
    ) -> Bool {
        settings.removesCameraBackgroundAfterRecording
            && settings.enabledSources.contains(.camera)
            && !settings.enabledSources.contains(.screen)
            && !hasEnabledAudioSource(settings)
            && fileExists(take.cameraURL)
            && take.cameraURL.pathExtension.lowercased() == "mov"
    }

    private static func hasEnabledAudioSource(_ settings: RecordingSettings) -> Bool {
        settings.enabledSources.contains(.microphone)
            || settings.enabledSources.contains(.systemAudio)
    }
}

protocol FinalVideoExporting {
    func exportFinalVideo(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        progressHandler: (@MainActor (Double) -> Void)?
    ) async throws -> URL
}

struct MergerFinalVideoExporter: FinalVideoExporting {
    func exportFinalVideo(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        progressHandler: (@MainActor (Double) -> Void)?
    ) async throws -> URL {
        try await Merger.exportFinalVideo(
            take: take,
            settings: settings,
            sceneEvents: sceneEvents,
            progressHandler: progressHandler
        )
    }
}
