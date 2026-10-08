import AppKit
import CoreGraphics

extension MainWindowController {
    struct ScreenCaptureSignature: Equatable {
        let usesPickedContent: Bool
        let selectionRevision: Int
        let windowGeometryRevision: Int
        let screenSourceBinding: ScreenSourceBinding?
        let selectedDisplayID: String?
        let screenCrop: CGRect?
        let framesPerSecond: Int
        let includeCursor: Bool
        let includesRecorderUI: Bool
        let isEditingCrop: Bool
    }

    private struct ScreenPreviewWatchdogRequest {
        let startRevision: Int
    }

    private func currentScreenCaptureSignature() -> ScreenCaptureSignature {
        let settings = coordinator.settings
        return ScreenCaptureSignature(
            usesPickedContent: settings.usesPickedScreenContent,
            selectionRevision: coordinator.screenContentSelectionRevision,
            windowGeometryRevision: coordinator.screenWindowGeometryRevision,
            screenSourceBinding: settings.screenSourceBinding,
            selectedDisplayID: settings.selectedDisplayID,
            screenCrop: settings.screenCrop,
            framesPerSecond: settings.framesPerSecond,
            includeCursor: settings.includeCursor,
            includesRecorderUI: settings.includesRecorderUI,
            isEditingCrop: viewModel.isScreenCropModeEnabled
        )
    }

    func restartScreenPreview() {
        viewModel.syncSettings()
        guard coordinator.state == .idle,
              idlePreviewIsAllowed else { return }

        if ScreenPreviewLifecycle.shouldReuse(.init(
            isRunning: coordinator.isScreenPreviewRunning,
            hasPreviewContent: previewStage.screenPreview.hasPreviewContent,
            screenEnabled: coordinator.settings.enabledSources.contains(.screen),
            screenHidden: coordinator.settings.hiddenSources.contains(.screen),
            captureSignatureMatches: currentScreenCaptureSignature() == lastStartedScreenCaptureSignature
        )) {
            refreshPermissionGate()
            return
        }

        switch ScreenPreviewLifecycle.action(settings: coordinator.settings) {
        case .preserveHidden:
            startScreenPreview()
        case .restart:
            Task {
                await coordinator.stopScreenPreview()
                guard idlePreviewIsAllowed else { return }
                startScreenPreview()
            }
        }
    }

    func cancelScreenPreviewWatchdog() {
        screenPreviewWatchdogTask?.cancel()
        screenPreviewWatchdogTask = nil
    }

    func startScreenPreview() {
        guard !LocalDevelopmentRuntime.disablesIdleCapture() else { return }
        guard coordinator.state == .idle, idlePreviewIsAllowed else { return }
        if coordinator.settings.hiddenSources.contains(.screen) {
            cancelScreenPreviewWatchdog()
            refreshPermissionGate()
            return
        }

        guard coordinator.settings.enabledSources.contains(.screen) else {
            screenPreviewStartRevision += 1
            cancelScreenPreviewWatchdog()
            Task { await coordinator.stopScreenPreview() }
            previewStage.screenPreview.setMessage("Screen source off")
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        guard coordinator.hasActiveScreenSourceSelection else {
            screenPreviewStartRevision += 1
            cancelScreenPreviewWatchdog()
            previewStage.screenPreview.setMessage("")
            viewModel.applyMessage("Choose a screen, app, or window to preview.")
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        if !previewStage.screenPreview.hasPreviewContent {
            previewStage.screenPreview.setMessage("Starting screen preview")
        }
        let captureSignature = currentScreenCaptureSignature()
        if screenPreviewRecoverySignature != captureSignature {
            screenPreviewRecoverySignature = captureSignature
            screenPreviewRecoveryAttempts = 0
        }
        lastStartedScreenCaptureSignature = captureSignature
        screenPreviewStartRevision += 1
        let previewStartRevision = screenPreviewStartRevision
        let previewSettings = coordinator.settings
        scheduleScreenPreviewWatchdog(.init(startRevision: previewStartRevision))
        Task { [weak self] in
            guard let self else { return }
            do {
                try await coordinator.startScreenPreview { [weak self] frame in
                    guard let self, self.coordinator.state == .idle,
                          self.screenPreviewStartRevision == previewStartRevision else { return }
                    self.screenPreviewRecoveryAttempts = 0
                    self.cancelScreenPreviewWatchdog()
                    self.previewStage.applyLiveFrameAspectRatio(frame.sourceAspectRatio)
                    self.previewStage.screenPreview.enqueuePreviewSampleBuffer(frame.sampleBuffer)
                }
                guard self.screenPreviewStartRevision == previewStartRevision else { return }
                refreshPermissionGate()
            } catch {
                guard self.screenPreviewStartRevision == previewStartRevision,
                      coordinator.state == .idle else { return }
                previewStage.screenPreview.setMessage("Screen preview unavailable")
                viewModel.applyMessage(
                    ScreenPreviewFailureMessage.detailMessage(for: error, settings: previewSettings)
                )
                lastStartedScreenCaptureSignature = nil
                refreshPermissionGate()
            }
        }
    }

    private func scheduleScreenPreviewWatchdog(_ request: ScreenPreviewWatchdogRequest) {
        screenPreviewWatchdogTask?.cancel()
        screenPreviewWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self,
                  !Task.isCancelled,
                  self.screenPreviewStartRevision == request.startRevision,
                  self.coordinator.state == .idle,
                  self.idlePreviewIsAllowed,
                  self.coordinator.settings.visibleSources.contains(.screen),
                  !self.previewStage.screenPreview.hasPreviewContent else { return }

            self.screenPreviewStartRevision += 1
            self.lastStartedScreenCaptureSignature = nil
            if self.screenPreviewRecoveryAttempts >= 2 {
                self.previewStage.screenPreview.setMessage("Screen preview unavailable")
                self.viewModel.applyMessage(
                    "Screen preview stopped responding. Re-select the screen source to reconnect."
                )
                self.screenPreviewWatchdogTask = nil
                return
            }

            self.screenPreviewRecoveryAttempts += 1
            self.previewStage.screenPreview.setMessage("Restarting screen preview")
            await self.coordinator.stopScreenPreview()
            try? await Task.sleep(for: .milliseconds(250))
            guard self.coordinator.state == .idle,
                  self.idlePreviewIsAllowed,
                  self.coordinator.settings.visibleSources.contains(.screen) else { return }
            self.startScreenPreview()
        }
    }
}
