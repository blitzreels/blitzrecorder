import BlitzRecorderCore
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
        sceneEvents: [RecordingSceneEvent] = [],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        if Self.shouldSaveTransparentCameraOnly(take: take, settings: settings, fileExists: fileExists) {
            action = .saveTransparentCameraOnly
        } else if let reason = Self.missingVisibleVideoReason(
            settings: settings,
            captureSummary: captureSummary,
            sceneEvents: sceneEvents
        ) {
            action = .recoverNoVideo(reason: reason)
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

    private static func missingVisibleVideoReason(
        settings: RecordingSettings,
        captureSummary: CaptureSourceRunSummary,
        sceneEvents: [RecordingSceneEvent]
    ) -> String? {
        let expectedSources = expectedVisibleVideoSources(settings: settings, sceneEvents: sceneEvents)
        guard !expectedSources.isEmpty else {
            return "No video frames captured"
        }

        let missingSources = expectedSources.filter { captureSummary.completions[$0]?.wroteMedia != true }
        guard !missingSources.isEmpty else { return nil }

        if missingSources == expectedSources {
            return "No video frames captured"
        }

        let names = missingSources.map { displayName(for: $0, settings: settings) }.joined(separator: " and ")
        return "\(names) video could not be finalized"
    }

    private static func expectedVisibleVideoSources(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> Set<CaptureSource> {
        let scenes = sceneEvents.map(\.scene)
        let visibleSources = scenes.isEmpty
            ? settings.visibleSources
            : Set(scenes.flatMap(\.enabledSources))
        return visibleSources.intersection([.screen, .camera])
    }

    private static func displayName(for source: CaptureSource, settings: RecordingSettings) -> String {
        switch source {
        case .camera where RemoteCameraProviderID.isRemote(settings.selectedCameraID):
            return "iPhone camera"
        case .camera:
            return "Camera"
        case .screen:
            return "Screen"
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System audio"
        }
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
