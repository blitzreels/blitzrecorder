import Foundation

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
