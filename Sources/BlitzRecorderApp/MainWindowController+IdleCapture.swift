import AppKit
import AVFoundation

extension MainWindowController {
    func scheduleIdlePreviewRestart(afterNanoseconds delayNanoseconds: UInt64) {
        idlePreviewRestartTask?.cancel()
        idlePreviewRestartTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self,
                  !Task.isCancelled,
                  self.coordinator.state == .idle else {
                return
            }
            self.restartScreenPreview()
            self.restartCameraPreview()
            self.idlePreviewRestartTask = nil
        }
    }

    func cancelScheduledIdlePreviewRestart() {
        idlePreviewRestartTask?.cancel()
        idlePreviewRestartTask = nil
    }

    func syncIdleCaptureResources(for mode: RecorderViewModel.StudioMode) {
        if mode.keepsIdleCaptureResourcesActive && viewModel.isLivePreviewEnabled {
            resumeIdleCaptureResources()
        } else {
            suspendIdleCaptureResources()
        }
    }

    private func resumeIdleCaptureResources() {
        guard !LocalDevelopmentRuntime.disablesIdleCapture(), idlePreviewIsAllowed else { return }
        let previousTask = studioModeCaptureResourceTask
        studioModeCaptureResourceTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self,
                  NSApp.isActive,
                  self.window?.isVisible == true,
                  self.coordinator.state == .idle,
                  self.idlePreviewIsAllowed else { return }
            await coordinator.resumeIdleAudioLevelMonitoring()
            guard NSApp.isActive,
                  self.window?.isVisible == true,
                  self.idlePreviewIsAllowed else { return }
            startScreenPreview()
            startCameraPreview()
        }
    }

    func suspendIdleCaptureResources() {
        guard coordinator.state == .idle else { return }
        cancelScheduledIdlePreviewRestart()
        screenPreviewStartRevision += 1
        cancelScreenPreviewWatchdog()
        lastStartedScreenCaptureSignature = nil
        invalidateCameraPreviewStart()
        cameraPreviewRecoveryAttempts = 0
        previewStage.screenPreview.setMessage("Preview paused")
        previewStage.cameraPreview.setMessage("Preview paused")
        coordinator.setLocalCameraRuntimeState(.unchecked)
        viewModel.micLevels.clear()
        viewModel.sysLevels.clear()
        viewModel.refreshPermissionStatus()
        refreshPermissionGate()
        let previousTask = studioModeCaptureResourceTask
        studioModeCaptureResourceTask = Task { [weak self] in
            _ = await previousTask?.result
            guard let self, self.coordinator.state == .idle else { return }
            await coordinator.suspendIdleCaptureResources()
        }
    }

    func invalidateCameraPreviewStart() {
        cameraPreviewWatchdogTask?.cancel()
        cameraPreviewWatchdogTask = nil
        cameraPreviewStartRevision += 1
        isStartingCameraPreview = false
        cameraPreviewDeviceID = nil
    }

    func refreshStartupState() {
        Task {
            guard idlePreviewIsAllowed else { return }
            coordinator.refreshAudioLevelMonitoring()
            viewModel.syncSettings()
            refreshPermissionGate()
        }
    }

    func refreshPermissionGate() {
        guard coordinator.state == .idle else { return }
        let readiness = coordinator.recordingReadiness()
        coordinator.permissionGate.writeDiagnostic(readiness)
        if !readiness.isReady {
            viewModel.applyMessage(shortReadinessMessage(readiness))
        } else if viewModel.detailMessage.hasPrefix("Screen permission") ||
                  viewModel.detailMessage.hasPrefix("Share a screen") ||
                  viewModel.detailMessage.hasPrefix("Pick a screen") ||
                  viewModel.detailMessage.hasPrefix("Enable BlitzRecorder") {
            viewModel.applyMessage("")
        }
    }

    private func shortReadinessMessage(_ readiness: RecordingReadiness) -> String {
        if readiness.isReady { return "" }
        if readiness.blockers.contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            if coordinator.settings.screenSourceBinding?.isConcreteSelection != true {
                return "Enable Screen Recording, then choose a screen source."
            }
            return "Enable Screen Recording to preview the selected source."
        }
        if let blocker = readiness.blockers.first {
            if blocker.permission == "Camera availability" {
                return blocker.status == "starting"
                    ? "Starting camera preview."
                    : "Camera unavailable. Choose another camera or close the app using it."
            }
            return "\(blocker.source.rawValue) permission required."
        }
        return ""
    }

    func startCameraDeviceMonitoring() {
        let center = NotificationCenter.default
        let names = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ]

        cameraDeviceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice else { return }
                if device.hasMediaType(.audio) {
                    Task { @MainActor [weak self] in
                        await self?.viewModel.refreshSources()
                    }
                    return
                }
                guard device.hasMediaType(.video) else { return }
                Task { @MainActor [weak self] in
                    self?.refreshCameraPicker()
                }
            }
        }
        cameraDeviceObservers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeIdleCaptureResources()
            }
        })
        cameraDeviceObservers.append(center.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendIdleCaptureResources()
            }
        })
    }
}
