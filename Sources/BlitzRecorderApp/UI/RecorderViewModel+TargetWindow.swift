import CoreGraphics
import Foundation

extension RecorderViewModel {
    func fitFrontWindowForShorts() {
        screenCaptureAreaSelection = .activeWindow
        fitCurrentScreenWindow(zoom: targetWindowZoom)
        syncSettings()
        refreshTargetWindow()
    }

    func fitScreenItemToFrontWindow() {
        screenCaptureAreaSelection = .activeWindow
        coordinator.fitScreenItemToFrontWindow()
        syncSettings()
        refreshTargetWindow()
    }

    func fitFrontWindowForShorts(zoom: CGFloat) {
        cancelScheduledTargetWindowFit()
        screenCaptureAreaSelection = .activeWindow
        targetWindowZoom = clampedTargetWindowZoom(zoom)
        coordinator.setScreenWindowZoom(targetWindowZoom)
        fitCurrentScreenWindow(zoom: targetWindowZoom)
        syncSettings()
        refreshTargetWindow()
    }

    func setTargetWindowZoom(_ zoom: CGFloat) {
        let previousZoom = max(0.001, targetWindowZoom)
        targetWindowZoom = clampedTargetWindowZoom(zoom)
        coordinator.setScreenContentMode(.fit)
        coordinator.setScreenWindowZoom(targetWindowZoom)
        scaleScreenLayer(aroundCenterBy: targetWindowZoom / previousZoom)
        settings = coordinator.settings
        guard settings.screenSourceBinding?.kind != .display else {
            cancelScheduledTargetWindowFit()
            syncSettings()
            return
        }
        screenCaptureAreaSelection = .activeWindow
        scheduleTargetWindowFit()
        syncSettings()
    }

    func applyTargetWindowZoom() {
        cancelScheduledTargetWindowFit()
        fitCurrentScreenWindow(zoom: targetWindowZoom)
        syncSettings()
        refreshTargetWindow()
    }

    func fitCurrentScreenWindowToSlot() {
        cancelScheduledTargetWindowFit()
        coordinator.setSceneLayer(
            .screen,
            frame: SceneSlotGeometry.targetWindowSlot(
                in: coordinator.settings.sceneLayout,
                enabledSources: coordinator.settings.visibleSources
            )
        )
        coordinator.setScreenCrop(nil)
        coordinator.setScreenContentMode(.fit)
        applyCurrentScreenWindowZoom(targetWindowZoom)
    }

    func zoomTargetWindowFit(by delta: CGFloat) {
        setTargetWindowZoom(targetWindowZoom + delta)
    }

    func resetTargetWindowZoom() {
        setTargetWindowZoom(1)
    }

    func zoomScreenSourceContentIn() {
        coordinator.zoomScreenSourceContent(.zoomIn)
    }

    func zoomScreenSourceContentOut() {
        coordinator.zoomScreenSourceContent(.zoomOut)
    }

    func resetScreenSourceContentZoom() {
        coordinator.zoomScreenSourceContent(.reset)
    }

    func resizeTargetWindow(widthDelta: CGFloat = 0, heightDelta: CGFloat = 0) {
        coordinator.resizeTargetWindow(widthDelta: widthDelta, heightDelta: heightDelta)
        syncSettings()
    }

    func setTargetWindowSize(width: CGFloat, height: CGFloat) {
        coordinator.setTargetWindowSize(width: width, height: height)
        syncSettings()
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        coordinator.setSceneLayerOrder(order)
        syncSettings()
    }

    func syncSettingsAfterSceneChange() {
        syncSettings()
        if settings.visibleSources.contains(.screen) {
            refreshTargetWindow()
        }
    }

    func fitCurrentScreenWindow(zoom: CGFloat) {
        if settings.usesPickedScreenContent {
            coordinator.fitPickedScreenWindowToSlot(zoom: zoom)
            return
        }
        if let binding = settings.screenSourceBinding, binding.kind != .display {
            coordinator.fitScreenSourceWindow(binding, zoom: zoom)
        } else {
            coordinator.fitFrontWindowForShorts(zoom: zoom)
        }
    }

    private func applyCurrentScreenWindowZoom(_ zoom: CGFloat) {
        screenCaptureAreaSelection = .activeWindow
        targetWindowZoom = clampedTargetWindowZoom(zoom)
        coordinator.setScreenWindowZoom(targetWindowZoom)
        fitCurrentScreenWindow(zoom: targetWindowZoom)
        syncSettings()
        refreshTargetWindow()
    }

    func scheduleTargetWindowFit() {
        cancelScheduledTargetWindowFit()
        let zoom = targetWindowZoom
        let context = scheduledTargetWindowFitContext()
        targetWindowZoomTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, let self else { return }
            guard self.scheduledTargetWindowFitContext() == context,
                  self.screenCaptureAreaSelection == .activeWindow else {
                return
            }
            self.targetWindowZoomTask = nil
            self.fitCurrentScreenWindow(zoom: zoom)
            self.syncSettings()
            self.refreshTargetWindow()
        }
    }

    func cancelScheduledTargetWindowFit() {
        targetWindowZoomTask?.cancel()
        targetWindowZoomTask = nil
    }

    var hasScheduledTargetWindowFit: Bool {
        targetWindowZoomTask != nil
    }

    func prepareForWindowClose() {
        cancelScheduledTargetWindowFit()
    }

    private func scheduledTargetWindowFitContext() -> ScheduledTargetWindowFitContext {
        ScheduledTargetWindowFitContext(
            areaSelection: screenCaptureAreaSelection,
            screenSourceBinding: settings.screenSourceBinding,
            usesPickedScreenContent: settings.usesPickedScreenContent
        )
    }

    func syncScreenCaptureAreaSelection() {
        if screenCaptureAreaSelection == .activeWindow {
            return
        }
        guard settings.screenCrop != nil else {
            screenCaptureAreaSelection = .fullDisplay
            return
        }
        screenCaptureAreaSelection = .manualCrop
    }

    private func scaleScreenLayer(aroundCenterBy ratio: CGFloat) {
        guard canEditScene, abs(ratio - 1) > 0.0001 else { return }
        coordinator.setSceneLayer(
            .screen,
            frame: SceneLayerResizing.scaled(
                coordinator.settings.sceneLayout.screenFrame,
                aroundCenterBy: ratio
            )
        )
    }

    private func clampedTargetWindowZoom(_ zoom: CGFloat) -> CGFloat {
        ScreenSourceZoomGeometry.clamped(zoom)
    }


    var hasActiveScreenPickerSelection: Bool {
        coordinator.hasActiveScreenSourceSelection
    }

    var activePickedScreenContentKind: ScreenSourceBinding.Kind? {
        coordinator.activePickedScreenContentKind
    }

    var supportsScreenWindowScaling: Bool {
        ScreenWindowFit.supportsScaling(.init(
            settings: settings,
            hasActivePickerSelection: hasActiveScreenPickerSelection,
            activePickedKind: activePickedScreenContentKind
        ))
    }

    var hasAccessibilityAccessForWindowControls: Bool {
        _ = permissionRefreshToken
        return coordinator.permissionGate.hasAccessibilityAccess
    }

    var canShowScreenWindowFitControls: Bool {
        _ = permissionRefreshToken
        guard supportsScreenWindowScaling else { return false }
        return ScreenWindowFit.canShowFitControls(.init(
            settings: settings,
            targetWindowInfo: targetWindowInfo,
            hasAccessibilityAccess: coordinator.permissionGate.hasAccessibilityAccess,
            canAdjustScreenCapture: canAdjustScreenCapture
        ))
    }

    func requestAccessibilityForWindowControls() {
        Task {
            let result = await coordinator.permissionGate.requestAccessibilityAccessForWindowControls()
            detailMessage = result.message
            refreshPermissionStatus()
            refreshTargetWindow()
        }
    }

}
