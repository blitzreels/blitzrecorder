import CoreGraphics
import Foundation

@MainActor
extension RecorderStudioConfiguration {
    func setSceneLayer(
        _ kind: SceneLayerKind,
        frame: CGRect,
        transition: RecordingSceneTransition = .cut
    ) {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        var screenCaptureConfigurationChanged = false
        switch kind {
        case .screen:
            let nextFrame = SceneLayerResizing.clamped(frame)
            if settings.sceneLayout.screenFrame != nextFrame, settings.screenCrop != nil {
                settings.screenCrop = nil
                screenCaptureConfigurationChanged = true
            }
            settings.sceneLayout.screenFrame = nextFrame
        case .camera:
            settings.sceneLayout.cameraFrame = SceneLayerResizing.clamped(frame)
        }
        persist()
        updateRecordingScene?(transition)
        if screenCaptureConfigurationChanged {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func setCameraCropAmount(_ amount: CGPoint) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraCropAmount = SourceCropGeometry.clampedAmount(amount)
        persist()
        updateRecordingScene?(.cut)
    }

    func setCameraCropPosition(_ position: CGPoint) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraCropPosition = SourceCropGeometry.clampedPosition(position)
        persist()
        updateRecordingScene?(.cut)
    }

    func setCanvasBackgroundStyle(_ style: CanvasBackgroundStyle) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasBackgroundStyle = style
        if !style.supportsBackgroundAnimation {
            settings.canvasBackgroundAnimated = false
        }
        persist()
        updateRecordingScene?(.cut)
    }

    func setCanvasBackgroundAnimated(_ animated: Bool) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasBackgroundAnimated = animated && settings.canvasBackgroundStyle.supportsBackgroundAnimation
        persist()
        updateRecordingScene?(.cut)
    }

    func setCanvasPadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasPadding = CaptureValueClamps.canvasPadding(padding)
        persist()
        updateRecordingScene?(.cut)
        autoFitSelectedScreenWindow?()
    }

    func setCameraContentMode(_ mode: CameraContentMode) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraContentMode = mode
        persist()
        updateRecordingScene?(.cut)
    }

    func setScreenContentMode(_ mode: CameraContentMode) {
        guard sceneChangeIsAllowed() else { return }
        settings.screenContentMode = mode
        persist()
        updateRecordingScene?(.cut)
    }

    func setCameraFramePadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraFramePadding = 0
        persist()
        updateRecordingScene?(.cut)
    }

    func setCameraShadowEnabled(_ enabled: Bool) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraShadowEnabled = enabled
        persist()
        updateRecordingScene?(.cut)
    }

    func setSceneLayout(_ sceneLayout: SceneLayout) {
        guard sceneChangeIsAllowed() else { return }
        let nextScreenFrame = SceneLayerResizing.clamped(sceneLayout.screenFrame)
        let nextCameraFrame = SceneLayerResizing.clamped(sceneLayout.cameraFrame)
        let screenCaptureConfigurationChanged = settings.sceneLayout.screenFrame != nextScreenFrame
            && settings.screenCrop != nil
        settings.selectedScenePreset = nil
        if screenCaptureConfigurationChanged {
            settings.screenCrop = nil
        }
        settings.sceneLayout.screenFrame = nextScreenFrame
        settings.sceneLayout.cameraFrame = nextCameraFrame
        settings.sceneLayout.layerOrder = sceneLayout.layerOrder
        persist()
        updateRecordingScene?(.cut)
        if screenCaptureConfigurationChanged {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func resetSceneLayout() {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        settings.sceneLayout = SceneLayout.defaultLayout(
            for: settings.layout,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        )
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func applyScenePreset(_ preset: ScenePreset) {
        guard sceneChangeIsAllowed() else { return }
        guard preset.supports(settings.layout) else { return }
        let cameraWasVisible = settings.visibleSources.contains(.camera)
        settings = RecordingSceneMutation.applyingPreset(
            preset,
            to: settings,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        )
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        let cameraIsVisible = settings.visibleSources.contains(.camera)
        if cameraWasVisible != cameraIsVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    func setScreenSplitHeight(_ height: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.layout == .vertical else { return }
        let cameraWasVisible = settings.visibleSources.contains(.camera)
        settings = RecordingSceneMutation.applyingScreenSplit(
            height: height,
            to: settings,
            screenAspectRatio: screenAspectRatio()
        )
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if !cameraWasVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    func setSideBySideLayout(_ request: SceneLayout.SideBySideRequest) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.sceneLayout.cameraSide != nil else { return }
        settings.sceneLayout = SceneLayout.sideBySideLayout(request)
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func setCameraInset(
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat
    ) {
        guard sceneChangeIsAllowed() else { return }
        let screenWasVisible = settings.visibleSources.contains(.screen)
        let cameraWasVisible = settings.visibleSources.contains(.camera)
        let mutation = RecordingSceneMutation.applyingCameraInset(
            alignment: alignment,
            shape: shape,
            size: size,
            to: settings,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        )
        settings = mutation.settings
        persist()
        updateRecordingScene?(.cut)
        if mutation.clearedScreenCrop || !screenWasVisible {
            onScreenCaptureConfigurationChanged?()
        }
        if !cameraWasVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    @discardableResult
    func fitScreenToAvailableSlot() -> CGRect {
        guard sceneChangeIsAllowed() else { return settings.sceneLayout.screenFrame }
        let screenSlot = SceneSlotGeometry.screenSlot(
            in: settings.sceneLayout,
            enabledSources: settings.enabledSources
        )
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = SceneLayerResizing.clamped(screenSlot)
        settings.screenCrop = nil
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        return settings.sceneLayout.screenFrame
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        guard sceneChangeIsAllowed() else { return }
        guard Set(order) == Set(SceneLayerKind.allCases),
              order.count == SceneLayerKind.allCases.count else {
            return
        }
        settings.selectedScenePreset = nil
        settings.sceneLayout.layerOrder = order
        persist()
        updateRecordingScene?(.sceneSwitch)
    }

    func fitSceneLayer(_ kind: SceneLayerKind, scale: CGFloat = 1) {
        let sourceAspectRatio: CGFloat
        switch kind {
        case .screen:
            sourceAspectRatio = screenAspectRatio()
        case .camera:
            sourceAspectRatio = cameraAspectRatio()
        }
        setSceneLayer(
            kind,
            frame: SceneLayerFit.frame(.init(
                kind: kind,
                layout: settings.sceneLayout,
                visibleSources: settings.visibleSources,
                removesCameraBackgroundAfterRecording: settings.removesCameraBackgroundAfterRecording,
                sourceAspectRatio: sourceAspectRatio,
                canvasAspectRatio: settings.layout.aspectRatio,
                scale: scale
            )),
            transition: .sceneSwitch
        )
    }

    func beginScreenCropEditing() {
        guard sceneChangeIsAllowed() else { return }
        if let next = RecordingSceneMutation.clearingIncompatibleScreenCrop(settings) {
            settings = next
            persist()
        }
        isEditingScreenCrop = true
        onScreenCaptureConfigurationChanged?()
    }

    func endScreenCropEditing() {
        guard isEditingScreenCrop else { return }
        isEditingScreenCrop = false
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenCrop(_ crop: CGRect?) {
        guard sceneChangeIsAllowed() else { return }
        if let crop {
            settings.screenCrop = CaptureValueClamps.persistedScreenCrop(crop)
        } else {
            settings.screenCrop = nil
        }
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenWindowZoom(_ zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        let zoom = ScreenSourceZoomGeometry.clamped(zoom)
        guard abs(settings.screenWindowZoom - zoom) > 0.0001 else { return }
        settings.screenWindowZoom = zoom
        persist()
    }

    func clearScreenCrop() {
        settings.screenCrop = nil
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
    }

    func clearCustomScreenCrop() {
        guard settings.screenCrop != nil else { return }
        clearScreenCrop()
    }

    func screenSettingsWithoutCrop() -> RecordingSettings {
        var settings = settings
        settings.screenCrop = nil
        return settings
    }

    func noteScreenSourceAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        currentPickedScreenSourceAspectRatio = aspectRatio
    }

    @discardableResult
    func refitCameraInsetFrame(sourceAspectRatio: CGFloat) -> Bool {
        let frame = settings.sceneLayout.cameraFrame
        guard SceneLayout.isCameraInsetFrame(frame) else { return false }
        let next = SceneLayout.cameraInsetFrame(
            for: settings.layout,
            alignment: SceneLayout.cameraInsetAlignment(for: frame),
            shape: settings.sceneLayout.cameraInsetShape(in: settings.layout),
            size: settings.sceneLayout.cameraInsetSize(in: settings.layout),
            sourceAspectRatio: sourceAspectRatio
        )
        let epsilon: CGFloat = 0.0005
        guard abs(next.minX - frame.minX) > epsilon
            || abs(next.minY - frame.minY) > epsilon
            || abs(next.width - frame.width) > epsilon
            || abs(next.height - frame.height) > epsilon else { return false }
        settings.sceneLayout.cameraFrame = next
        return true
    }

    private func sceneChangeIsAllowed() -> Bool {
        guard allowsSceneChanges else {
            onMessage?("Scene layout is locked while saving.")
            return false
        }
        return true
    }
}
