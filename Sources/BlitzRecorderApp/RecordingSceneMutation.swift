import CoreGraphics
import Foundation

enum RecordingSceneMutation {
    struct Result {
        var settings: RecordingSettings
        var clearedScreenCrop: Bool
    }

    static func applyingPreset(
        _ preset: ScenePreset,
        to settings: RecordingSettings,
        screenAspectRatio: CGFloat,
        cameraAspectRatio: CGFloat
    ) -> RecordingSettings {
        var settings = settings
        settings.selectedScenePreset = preset
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: screenAspectRatio,
            cameraAspectRatio: cameraAspectRatio
        )
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        switch preset {
        case .webcamFullscreen:
            settings.hiddenSources.remove(.camera)
            settings.hiddenSources.insert(.screen)
            settings.screenCrop = nil
        case .screenFullscreen:
            settings.hiddenSources.remove(.screen)
            settings.hiddenSources.insert(.camera)
            settings.screenCrop = nil
        default:
            settings.hiddenSources.remove(.screen)
            settings.hiddenSources.remove(.camera)
        }
        return settings
    }

    enum PresetActivation: Equatable {
        case apply
        case pickScreenThenApply
    }

    static func screenSourceActivation(
        isScreenConfigured: Bool,
        hasActiveScreenSourceSelection: Bool
    ) -> PresetActivation {
        if !isScreenConfigured, !hasActiveScreenSourceSelection {
            return .pickScreenThenApply
        }
        return .apply
    }

    static func presetActivation(
        _ preset: ScenePreset,
        isScreenConfigured: Bool,
        hasActiveScreenSourceSelection: Bool
    ) -> PresetActivation {
        guard preset.enablesScreenSource else { return .apply }
        return screenSourceActivation(
            isScreenConfigured: isScreenConfigured,
            hasActiveScreenSourceSelection: hasActiveScreenSourceSelection
        )
    }

    static func applyingScreenSplit(
        height: CGFloat,
        to settings: RecordingSettings,
        screenAspectRatio: CGFloat
    ) -> RecordingSettings {
        var settings = settings
        settings.selectedScenePreset = .screenTop50
        settings.sceneLayout = SceneLayout.screenSplitLayout(
            screenHeight: height,
            screenAspectRatio: screenAspectRatio
        )
        settings.screenCrop = nil
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        settings.hiddenSources.remove(.screen)
        settings.hiddenSources.remove(.camera)
        return settings
    }

    static func applyingCameraInset(
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat,
        to settings: RecordingSettings,
        screenAspectRatio: CGFloat,
        cameraAspectRatio: CGFloat
    ) -> Result {
        var settings = settings
        let nextScreenFrame = SceneLayout.canvasFillingFrame(
            sourceAspectRatio: screenAspectRatio,
            canvasAspectRatio: settings.layout.aspectRatio
        )
        let clearedScreenCrop = settings.sceneLayout.screenFrame != nextScreenFrame
            && settings.screenCrop != nil
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = nextScreenFrame
        settings.sceneLayout.cameraFrame = SceneLayout.cameraInsetFrame(
            for: settings.layout,
            alignment: alignment,
            shape: shape,
            size: size,
            sourceAspectRatio: cameraAspectRatio
        )
        settings.sceneLayout.layerOrder = [.screen, .camera]
        settings.enabledSources.insert(.screen)
        settings.enabledSources.insert(.camera)
        settings.hiddenSources.remove(.screen)
        settings.hiddenSources.remove(.camera)
        if clearedScreenCrop {
            settings.screenCrop = nil
        }
        return Result(settings: settings, clearedScreenCrop: clearedScreenCrop)
    }

    static func defaultsForLayout(
        _ layout: CaptureLayout,
        screenAspectRatio: CGFloat,
        cameraAspectRatio: CGFloat
    ) -> (preset: ScenePreset, layout: SceneLayout) {
        (
            ScenePreset.defaultPreset(for: layout),
            SceneLayout.defaultLayout(
                for: layout,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        )
    }

    static func clearingIncompatibleScreenCrop(_ settings: RecordingSettings) -> RecordingSettings? {
        guard settings.layout == .horizontal,
              let screenCrop = settings.screenCrop,
              screenCrop.width > 0,
              screenCrop.height > 0,
              screenCrop.width / screenCrop.height < 1 else {
            return nil
        }
        var settings = settings
        settings.screenCrop = nil
        return settings
    }
}
