import AppKit
import AVFoundation

extension MainWindowController {
    func restartCameraPreview(isRecovery: Bool = false) {
        viewModel.syncSettings()
        guard coordinator.state == .idle,
              idlePreviewIsAllowed else { return }
        if !isRecovery { cameraPreviewRecoveryAttempts = 0 }
        if coordinator.isRemoteCameraSelected {
            startCameraPreview()
            return
        }
        invalidateCameraPreviewStart()
        let restartRevision = cameraPreviewStartRevision
        previewStage.cameraPreview.setMessage("Restarting camera")
        coordinator.setLocalCameraRuntimeState(.starting)
        viewModel.refreshPermissionStatus()
        refreshPermissionGate()
        Task {
            await coordinator.stopCameraPreview()
            guard cameraPreviewStartRevision == restartRevision,
                  coordinator.state == .idle,
                  IdleCameraPreviewPolicy.shouldStart(currentIdleCameraPreviewRequest()) else { return }
            startCameraPreview()
        }
    }

    func noteCameraPreviewFrame() {
        guard coordinator.state == .idle,
              idlePreviewIsAllowed,
              !coordinator.isRemoteCameraSelected,
              coordinator.settings.visibleSources.contains(.camera),
              previewStage.cameraPreview.hasPreviewContent else { return }
        let wasStarting = isStartingCameraPreview
        isStartingCameraPreview = false
        coordinator.setLocalCameraRuntimeState(.ready)
        scheduleCameraPreviewWatchdog()
        if wasStarting {
            viewModel.refreshPermissionStatus()
            refreshPermissionGate()
        }
    }

    private func scheduleCameraPreviewWatchdog() {
        cameraPreviewWatchdogTask?.cancel()
        let startRevision = cameraPreviewStartRevision
        cameraPreviewWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self,
                  self.cameraPreviewStartRevision == startRevision,
                  self.coordinator.state == .idle,
                  IdleCameraPreviewPolicy.shouldStart(self.currentIdleCameraPreviewRequest()),
                  !self.coordinator.isRemoteCameraSelected,
                  self.coordinator.settings.visibleSources.contains(.camera) else { return }
            if self.cameraPreviewRecoveryAttempts < 1 {
                self.cameraPreviewRecoveryAttempts += 1
                self.restartCameraPreview(isRecovery: true)
                return
            }
            self.invalidateCameraPreviewStart()
            self.previewStage.cameraPreview.setMessage("No camera video. Retry camera in Sources.")
            self.coordinator.setLocalCameraRuntimeState(.unavailable("No camera video received"))
            self.viewModel.refreshPermissionStatus()
            self.refreshPermissionGate()
            await self.coordinator.stopCameraPreview()
        }
    }

    private func currentIdleCameraPreviewRequest() -> IdleCameraPreviewRequest {
        IdleCameraPreviewRequest(
            appIsActive: NSApp.isActive,
            windowIsVisible: window?.isVisible == true,
            keepsIdleCaptureResourcesActive: idlePreviewIsAllowed
        )
    }

    private func stopIdleCameraPreview(message: String) {
        invalidateCameraPreviewStart()
        cameraPreviewRecoveryAttempts = 0
        coordinator.setLocalCameraRuntimeState(.unchecked)
        Task { await coordinator.stopCameraPreview() }
        previewStage.cameraPreview.setMessage(message)
        previewStage.cameraPreview.isHidden = true
        cameraPreviewDeviceID = nil
        isStartingCameraPreview = false
    }

    func startCameraPreview() {
        guard !LocalDevelopmentRuntime.disablesIdleCapture() else { return }
        guard IdleCameraPreviewPolicy.shouldStart(currentIdleCameraPreviewRequest()) else { return }
        if coordinator.settings.hiddenSources.contains(.camera) {
            stopIdleCameraPreview(message: "Camera source hidden")
            return
        }

        guard coordinator.settings.enabledSources.contains(.camera) else {
            stopIdleCameraPreview(message: "Camera source off")
            return
        }

        let selectedID = coordinator.settings.selectedCameraID
        if coordinator.isRemoteCameraSelected {
            coordinator.setLocalCameraRuntimeState(.unchecked)
            previewStage.cameraPreview.isHidden = false
            cameraPreviewDeviceID = selectedID
            let name = coordinator.selectedRemoteCameraName() ?? "Remote iPhone"
            let status = coordinator.selectedRemoteCameraStatus() ?? "Waiting for iPhone video"
            switch coordinator.selectedRemoteCameraConnectionState() {
            case .connected:
                if previewStage.cameraPreview.hasPreviewContent {
                    refreshPermissionGate()
                    return
                }
            case .pairing, .degraded, .disconnected, .discovering, .unavailable, nil:
                previewStage.cameraPreview.setMessage("\(name): \(status)")
                viewModel.clearRemoteCameraPreview(message: status)
                refreshPermissionGate()
                return
            }
            previewStage.cameraPreview.setMessage("\(name): \(status)")
            refreshPermissionGate()
            return
        }

        switch coordinator.permissionGate.cameraAuthorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            coordinator.setLocalCameraRuntimeState(.unchecked)
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Allow Camera to preview")
            cameraPreviewDeviceID = nil
            guard !isStartingCameraPreview else {
                refreshPermissionGate()
                return
            }
            isStartingCameraPreview = true
            Task {
                let granted = await coordinator.permissionGate.requestCameraAccess()
                isStartingCameraPreview = false
                if granted, idlePreviewIsAllowed {
                    startCameraPreview()
                } else {
                    previewStage.cameraPreview.setMessage("Camera permission required")
                }
                refreshPermissionGate()
            }
            refreshPermissionGate()
            return
        case .denied, .restricted:
            coordinator.setLocalCameraRuntimeState(.unchecked)
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Camera permission required")
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            refreshPermissionGate()
            return
        @unknown default:
            coordinator.setLocalCameraRuntimeState(.unavailable("Camera authorization is unavailable"))
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Camera unavailable")
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            refreshPermissionGate()
            return
        }

        if isStartingCameraPreview, cameraPreviewDeviceID == selectedID {
            coordinator.setLocalCameraRuntimeState(.starting)
            return
        }
        if previewStage.cameraPreview.hasPreviewContent, cameraPreviewDeviceID == selectedID {
            coordinator.setLocalCameraRuntimeState(.ready)
            refreshPermissionGate()
            return
        }

        previewStage.cameraPreview.isHidden = false
        cameraPreviewDeviceID = selectedID
        isStartingCameraPreview = true
        cameraPreviewStartRevision += 1
        let startRevision = cameraPreviewStartRevision
        coordinator.setLocalCameraRuntimeState(.starting)
        scheduleCameraPreviewWatchdog()
        viewModel.refreshPermissionStatus()
        refreshPermissionGate()
        previewStage.cameraPreview.setMessage("Starting camera")
        Task {
            do {
                if coordinator.settings.removesCameraBackgroundAfterRecording {
                    previewStage.cameraPreview.setMessage("Starting cutout")
                    try await coordinator.startCameraCutoutPreview { [weak self] image in
                        guard let self,
                              self.cameraPreviewStartRevision == startRevision,
                              self.idlePreviewIsAllowed,
                              self.coordinator.settings.visibleSources.contains(.camera) else {
                            return
                        }
                        self.previewStage.cameraPreview.setPreviewImage(image)
                        self.noteCameraPreviewFrame()
                    }
                    guard cameraPreviewStartRevision == startRevision else { return }
                    guard IdleCameraPreviewPolicy.shouldStart(currentIdleCameraPreviewRequest()),
                          coordinator.settings.visibleSources.contains(.camera) else {
                        await coordinator.stopCameraPreview()
                        return
                    }
                } else {
                    let layer = try await coordinator.cameraPreviewLayer()
                    guard cameraPreviewStartRevision == startRevision else { return }
                    guard IdleCameraPreviewPolicy.shouldStart(currentIdleCameraPreviewRequest()),
                          coordinator.settings.visibleSources.contains(.camera) else {
                        await coordinator.stopCameraPreview()
                        previewStage.cameraPreview.setMessage("Camera source off")
                        previewStage.cameraPreview.isHidden = true
                        cameraPreviewDeviceID = nil
                        isStartingCameraPreview = false
                        return
                    }
                    previewStage.cameraPreview.setPreviewLayer(layer)
                }
                cameraPreviewDeviceID = coordinator.settings.selectedCameraID
                noteCameraPreviewFrame()
                refreshPermissionGate()
            } catch {
                guard cameraPreviewStartRevision == startRevision,
                      idlePreviewIsAllowed else { return }
                isStartingCameraPreview = false
                cameraPreviewDeviceID = nil
                cameraPreviewWatchdogTask?.cancel()
                cameraPreviewWatchdogTask = nil
                previewStage.cameraPreview.setMessage("Camera unavailable")
                coordinator.setLocalCameraRuntimeState(.unavailable(error.localizedDescription))
                viewModel.refreshPermissionStatus()
                viewModel.applyMessage("Camera preview failed: \(error.localizedDescription)")
                refreshPermissionGate()
            }
        }
    }

    func showRecordingCameraPreview() {
        guard coordinator.settings.visibleSources.contains(.camera) else {
            return
        }
        if coordinator.isRemoteCameraSelected {
            if !previewStage.cameraPreview.hasPreviewContent {
                previewStage.cameraPreview.setMessage("Remote iPhone recording")
            }
            return
        }
        guard coordinator.settings.removesCameraBackgroundAfterRecording else { return }
        cameraPreviewDeviceID = nil
        previewStage.cameraPreview.setMessage("Camera live")
        Task {
            do {
                let layer = try await coordinator.cameraPreviewLayer()
                previewStage.cameraPreview.setPreviewLayer(layer)
                cameraPreviewDeviceID = coordinator.settings.selectedCameraID
            } catch {
                previewStage.cameraPreview.setMessage("Camera recording")
            }
        }
    }

    func refreshCameraPicker() {
        viewModel.refreshPermissionStatus()
        Task {
            await viewModel.refreshSources()
            viewModel.refreshRemoteCameraState()
            startCameraPreview()
            refreshPermissionGate()
        }
    }
}
