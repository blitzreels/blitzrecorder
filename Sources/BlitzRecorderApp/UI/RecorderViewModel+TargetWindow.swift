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
        guard canAdjustScreenCapture else { return }
        let canResizeWindow = supportsScreenWindowScaling
        coordinator.cancelPendingScreenWindowFits()
        let requestedZoom = clampedTargetWindowZoom(zoom)
        if canResizeWindow {
            if coordinator.settings.screenCrop != nil { coordinator.setScreenCrop(nil) }
            if coordinator.settings.screenContentMode != .fit { coordinator.setScreenContentMode(.fit) }
        }
        coordinator.setScreenWindowZoom(requestedZoom)
        targetWindowZoom = requestedZoom
        settings = coordinator.settings
        guard canResizeWindow else {
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
        guard canAdjustScreenCapture, supportsScreenWindowScaling else { return }
        fitCurrentScreenWindow(zoom: targetWindowZoom)
        syncSettings()
        refreshTargetWindow()
    }

    func fitCurrentScreenWindowToSlot() {
        guard canAdjustScreenCapture, supportsScreenWindowScaling else { return }
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
        let context = scheduledTargetWindowFitContext()
        guard targetWindowZoomTask == nil || pendingTargetWindowFitContext != context else { return }
        cancelScheduledTargetWindowFit()
        pendingTargetWindowFitContext = context
        targetWindowZoomTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            self.targetWindowZoomTask = nil
            self.pendingTargetWindowFitContext = nil
            guard self.scheduledTargetWindowFitContext() == context,
                  self.canAdjustScreenCapture,
                  self.supportsScreenWindowScaling,
                  self.screenCaptureAreaSelection == .activeWindow else {
                return
            }
            self.fitCurrentScreenWindow(zoom: self.targetWindowZoom)
            self.syncSettings()
        }
    }

    func cancelScheduledTargetWindowFit() {
        targetWindowZoomTask?.cancel()
        targetWindowZoomTask = nil
        pendingTargetWindowFitContext = nil
        coordinator.cancelPendingScreenWindowFits()
    }

    var hasScheduledTargetWindowFit: Bool {
        targetWindowZoomTask != nil
    }

    func prepareForWindowClose() {
        cancelScheduledTargetWindowFit()
        cancelPendingPermissionRequests()
    }

    private func scheduledTargetWindowFitContext() -> ScheduledTargetWindowFitContext {
        ScheduledTargetWindowFitContext(
            areaSelection: screenCaptureAreaSelection,
            screenSourceBinding: settings.screenSourceBinding,
            usesPickedScreenContent: settings.usesPickedScreenContent,
            sceneID: coordinator.selectedSceneIDForCurrentLayout(),
            layout: settings.layout,
            screenFrame: settings.sceneLayout.screenFrame,
            canvasPadding: settings.canvasPadding
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
        startPermissionRequest { [weak self] in
            guard let self else { return }
            let result = await coordinator.permissionGate.requestAccessibilityAccessForWindowControls()
            guard !Task.isCancelled, result.status != .cancelled else { return }
            detailMessage = result.message
            refreshPermissionStatus()
            refreshTargetWindow()
        }
    }

}
