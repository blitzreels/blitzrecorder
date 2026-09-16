import Foundation

extension RecorderViewModel {
    func setScenePreset(_ preset: ScenePreset) {
        cancelScreenSplitPreview()
        applySceneMutation(
            RecordingSceneMutation.presetActivation(
                preset,
                isScreenConfigured: isSourceConfigured(.screen),
                hasActiveScreenSourceSelection: coordinator.hasActiveScreenSourceSelection
            )
        ) {
            self.coordinator.applyScenePreset(preset)
        }
    }

    func setCameraContentMode(_ mode: CameraContentMode) {
        coordinator.setCameraContentMode(mode)
        syncSettingsAfterSceneChange()
    }

    func setScreenContentMode(_ mode: CameraContentMode) {
        coordinator.setScreenContentMode(mode)
        syncSettingsAfterSceneChange()
    }

    func setCameraFramePadding(_ padding: Double) {
        coordinator.setCameraFramePadding(CGFloat(padding))
        syncSettingsAfterSceneChange()
    }

    func setCameraShadowEnabled(_ enabled: Bool) {
        coordinator.setCameraShadowEnabled(enabled)
        syncSettingsAfterSceneChange()
    }

    func setCameraInsetAlignment(_ alignment: CameraInsetAlignment) {
        setCameraInset(
            alignment: alignment,
            shape: cameraInsetShape,
            size: CGFloat(cameraInsetSize)
        )
    }

    func setCameraInsetShape(_ shape: CameraInsetShape) {
        setCameraInset(
            alignment: cameraInsetAlignment,
            shape: shape,
            size: CGFloat(cameraInsetSize)
        )
    }

    func setCameraInsetSize(_ size: Double) {
        setCameraInset(
            alignment: cameraInsetAlignment,
            shape: cameraInsetShape,
            size: CGFloat(size)
        )
    }

    func fitScreenToAvailableSlot() {
        coordinator.fitScreenToAvailableSlot()
        syncSettingsAfterSceneChange()
    }

    func resetSceneLayout() {
        coordinator.resetSceneLayout()
        syncSettingsAfterSceneChange()
    }

    func setCameraInset(
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat
    ) {
        applySceneMutation(
            RecordingSceneMutation.screenSourceActivation(
                isScreenConfigured: isSourceConfigured(.screen),
                hasActiveScreenSourceSelection: coordinator.hasActiveScreenSourceSelection
            )
        ) {
            self.coordinator.setCameraInset(alignment: alignment, shape: shape, size: size)
        }
    }

    func applySceneMutation(
        _ activation: RecordingSceneMutation.PresetActivation,
        _ mutate: @escaping () -> Void
    ) {
        switch activation {
        case .pickScreenThenApply:
            Task { [self] in
                do {
                    try await coordinator.pickScreenSource()
                    mutate()
                    syncSettingsAfterSceneChange()
                    detailMessage = RecorderStudioLabels.screenSelectedForSession
                } catch {
                    detailMessage = RecorderStudioLabels.screenPickerFailed(error)
                }
            }
        case .apply:
            mutate()
            syncSettingsAfterSceneChange()
        }
    }

    var isSelectedLayerEnabled: Bool {
        settings.enabledSources.contains(selectedLayer.source)
    }

    var canEditScene: Bool {
        RecorderStudioEditPolicy.canEdit(state: state)
    }

    var canAdjustScreenCapture: Bool {
        RecorderStudioEditPolicy.canEdit(state: state)
    }

    var canManipulateCanvasItems: Bool {
        canEditScene
    }

    var canApplyCanvasEdit: Bool {
        canManipulateCanvasItems && previewStage.sceneID == coordinator.selectedSceneIDForCurrentLayout()
    }

    var canEditCameraCrop: Bool {
        canEditScene
    }

    var currentScreenSourceAspectRatio: CGFloat {
        coordinator.currentScreenSourceAspectRatio()
    }

    var currentCameraSourceAspectRatio: CGFloat {
        coordinator.currentCameraSourceAspectRatio()
    }

    func syncPreviewInteractionState() {
        previewStage.allowsLayerInteraction = canManipulateCanvasItems && !isScreenCropModeEnabled && !isCameraCropModeEnabled
        previewStage.allowsCameraCropInteraction = canEditCameraCrop
        if !canEditCameraCrop {
            previewStage.cancelCameraCropEditing()
            isCameraCropModeEnabled = false
            cancelScreenCropMode()
        }
    }

    func selectLayer(_ layer: SceneLayerKind) {
        guard settings.enabledSources.contains(layer.source) else { return }
        inspectorSelection = .source(layer.source)
        previewStage.isBackgroundLayerSelected = false
        previewStage.selectedLayer = layer
    }

    func selectBackgroundLayer() {
        inspectorSelection = .canvas
        previewStage.isBackgroundLayerSelected = true
    }

    func selectSource(_ source: CaptureSource) {
        guard isSourceConfigured(source) else { return }
        inspectorSelection = .source(source)
        previewStage.isBackgroundLayerSelected = false
        switch source {
        case .screen:
            selectLayer(.screen)
        case .camera:
            selectLayer(.camera)
        case .microphone, .systemAudio:
            break
        }
    }

    func fitSelectedLayer() {
        coordinator.fitSceneLayer(selectedLayer)
        syncSettings()
    }

    func fitSelectedLayer(scale: CGFloat) {
        coordinator.fitSceneLayer(selectedLayer, scale: scale)
        syncSettings()
    }

    func finishSceneLayerResize(_ layer: SceneLayerKind) {
        guard layer == .screen, supportsScreenWindowScaling else { return }
        screenCaptureAreaSelection = .activeWindow
        scheduleTargetWindowFit()
    }

    func setScreenSource(_ binding: ScreenSourceBinding) {
        cancelScheduledTargetWindowFit()
        if binding.kind == .application {
            lastApplicationScreenSourceBinding = binding
        }
        let autoFitWindowZoom = binding.kind == .display ? nil : targetWindowZoom
        coordinator.setScreenSource(binding, autoFitWindowZoom: autoFitWindowZoom)
        syncSettings()
        screenCaptureAreaSelection = binding.kind == .display ? .fullDisplay : .activeWindow
        detailMessage = state == .idle ? "Screen source set to \(binding.displayName)." : "Switching screen source…"
    }

    var canUseAppOnlyCapture: Bool {
        ScreenSourceCatalog.canUseAppOnlyCapture(
            current: settings.screenSourceBinding,
            lastApplication: lastApplicationScreenSourceBinding,
            available: availableScreenSources
        )
    }

    func setAppOnlyCapture(_ enabled: Bool) {
        if enabled {
            guard settings.screenSourceBinding?.kind != .application else { return }
            let binding = lastApplicationScreenSourceBinding
                ?? availableScreenSources.first(where: { $0.binding.kind == .application })?.binding
            guard let binding else { return }
            setScreenSource(binding)
        } else if settings.screenSourceBinding?.kind == .application {
            setFullDisplayScreenCapture()
        }
    }

    func setWindowOnlyCapture() {
        cancelScheduledTargetWindowFit()
        if settings.screenSourceBinding?.kind == .window {
            screenCaptureAreaSelection = .activeWindow
            fitCurrentScreenWindow(zoom: targetWindowZoom)
            syncSettings()
            refreshTargetWindow()
            return
        }
        if let binding = preferredWindowBindingForCurrentSource() {
            setScreenSource(binding)
            return
        }
        if settings.screenSourceBinding?.kind == .application {
            detailMessage = "No window source available for \(settings.screenSourceBinding?.displayName ?? "this app")."
            return
        }
        fitScreenItemToFrontWindow()
    }

    func setFullDisplayScreenCapture() {
        cancelScheduledTargetWindowFit()
        cancelScreenCropMode()
        let displayID = settings.screenSourceBinding?.displayID ?? settings.selectedDisplayID
        coordinator.setScreenSource(.display(id: displayID))
        coordinator.clearScreenCrop()
        syncSettings()
        screenCaptureAreaSelection = .fullDisplay
        detailMessage = "Screen source set to full display."
    }

    func preferredWindowBindingForCurrentSource() -> ScreenSourceBinding? {
        guard let currentSource = settings.screenSourceBinding else { return nil }
        return ScreenSourceCatalog.preferredWindowBinding(
            context: WindowSourceSelectionContext(
                currentSource: currentSource,
                targetWindow: targetWindowInfo,
                availableSources: availableScreenSources
            )
        )
    }

    func syncSelectedSource() {
        guard case .source = inspectorSelection else {
            return
        }
        if let source = inspectorSelection.source, isSourceConfigured(source) {
            return
        }
        inspectorSelection = RecorderInspectorSelection.initial(settings: settings)
        if let selectedLayer = inspectorSelection.sceneLayer {
            previewStage.selectedLayer = selectedLayer
        }
    }

}
