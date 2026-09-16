import Foundation
import ScreenCaptureKit

struct TakeStartPlan {
    let usesRemoteCamera: Bool
    let usesLiveCompositor: Bool
    let localCaptureSettings: RecordingSettings
    let sceneTimelineSettings: RecordingSettings

    @MainActor
    static func make(settings: RecordingSettings, isRemoteCameraSelected: Bool) -> TakeStartPlan {
        let usesRemoteCamera = settings.enabledSources.contains(.camera) && isRemoteCameraSelected
        var localCaptureSettings = settings
        if usesRemoteCamera {
            localCaptureSettings.enabledSources.remove(.camera)
        }
        return TakeStartPlan(
            usesRemoteCamera: usesRemoteCamera,
            usesLiveCompositor: TakeRecordingRuntime.shouldUseLiveCompositor(
                settings: settings,
                isRemoteCameraSelected: isRemoteCameraSelected
            ),
            localCaptureSettings: localCaptureSettings,
            sceneTimelineSettings: settings
        )
    }
}

enum RecordingStartAccess {
    struct Needed: Equatable {
        var remoteCamera: Bool
        var localCamera: Bool
        var microphone: Bool
        var stopLocalCameraSession: Bool
        var stopScreenPreview: Bool
    }

    static func needed(enabledSources: Set<CaptureSource>, plan: TakeStartPlan) -> Needed {
        Needed(
            remoteCamera: plan.usesRemoteCamera,
            localCamera: enabledSources.contains(.camera) && !plan.usesRemoteCamera,
            microphone: enabledSources.contains(.microphone),
            stopLocalCameraSession: plan.usesLiveCompositor && enabledSources.contains(.camera),
            stopScreenPreview: plan.usesLiveCompositor && enabledSources.contains(.screen)
        )
    }
}

struct RecordingStartPrepared {
    let recordingSettings: RecordingSettings
    let initialScene: RecordingScene
    let skippedSystemAudio: Bool
    let startPlan: TakeStartPlan
    let access: RecordingStartAccess.Needed
    let remoteTakeID: UUID?

    @MainActor
    static func make(
        requestedSettings: RecordingSettings,
        recordingSettings: RecordingSettings,
        isRemoteCameraSelected: Bool,
        pickedFilter: SCContentFilter?
    ) -> RecordingStartPrepared {
        let startPlan = TakeStartPlan.make(
            settings: recordingSettings,
            isRemoteCameraSelected: isRemoteCameraSelected
        )
        return RecordingStartPrepared(
            recordingSettings: recordingSettings,
            initialScene: RecordingScene.live(
                settings: recordingSettings,
                pickedFilter: pickedFilter
            ),
            skippedSystemAudio: RecordingStartGate.skippedSystemAudio(
                requested: requestedSettings.enabledSources,
                effective: recordingSettings.enabledSources
            ),
            startPlan: startPlan,
            access: RecordingStartAccess.needed(
                enabledSources: recordingSettings.enabledSources,
                plan: startPlan
            ),
            remoteTakeID: RecordingStartGate.remoteTakeID(plan: startPlan)
        )
    }
}
