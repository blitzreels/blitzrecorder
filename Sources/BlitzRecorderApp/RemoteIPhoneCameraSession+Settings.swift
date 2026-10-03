import BlitzRecorderCore
import BlitzRecorderTransport
import CoreGraphics
import Foundation

extension RemoteIPhoneCameraSession {
    func selectedName() -> String? {
        sessionState.selectedName(settings: readSettings())
    }

    func selectedStatus() -> String? {
        sessionState.selectedStatus(
            settings: readSettings(),
            previewHealthStatus: Self.previewHealthStatus
        )
    }

    func selectedConnectionState() -> RemoteCameraConnectionState? {
        guard let selectedServiceID = selectedRemoteServiceID() else {
            return nil
        }
        return sessionState.connectionState(for: selectedServiceID)
    }

    func selectedDeviceDescription() -> String {
        sessionState.selectedDeviceDescription(
            settings: readSettings(),
            marketingName: Self.iPhoneMarketingName
        )
    }

    func selectedCapabilities() -> RemoteCameraCapabilities? {
        sessionState.selectedCapabilities(
            settings: readSettings(),
            normalizedSettings: { normalizedSettings($0, for: $1) }
        )
    }

    func selectedTelemetry() -> RemoteCameraTelemetry? {
        sessionState.selectedTelemetry(
            settings: readSettings(),
            normalizedSettings: { normalizedSettings($0, for: $1) }
        )
    }

    func deviceSummaries() -> [RemoteCameraDeviceSummary] {
        sessionState.deviceSummaries(
            settings: readSettings(),
            marketingName: Self.iPhoneMarketingName,
            previewHealthStatus: Self.previewHealthStatus
        )
    }

    func cameraOptions() -> [SourceOption] {
        sessionState.cameraOptions()
    }

    func applySettingsIntent(_ intent: RemoteCameraSettingsIntent) {
        guard let selectedServiceID = selectedRemoteServiceID() else {
            return
        }
        let settings = readSettings()
        let result = RemoteCameraSettingsCommand.apply(
            intent,
            to: remoteSettings(for: selectedServiceID),
            capabilities: sessionState.capabilities[selectedServiceID],
            preferredFrameRate: settings.framesPerSecond
        )
        if let message = result.message {
            onMessage?(message)
        }
        guard result.didChange else { return }
        commitSettings(result.settings, serviceID: selectedServiceID)
    }

    func resetSettings() {
        guard let selectedServiceID = selectedRemoteServiceID() else {
            return
        }
        let settings = readSettings()
        let result = RemoteCameraSettingsCommand.apply(
            .resetAll(frameRate: settings.framesPerSecond),
            to: remoteSettings(for: selectedServiceID),
            capabilities: sessionState.capabilities[selectedServiceID],
            preferredFrameRate: settings.framesPerSecond
        )
        commitSettings(result.settings, serviceID: selectedServiceID, sendImmediately: true)
    }

    func sendSettings() {
        guard let selectedServiceID = selectedRemoteServiceID() else {
            return
        }
        settingsSendTasks[selectedServiceID]?.cancel()
        settingsSendTasks[selectedServiceID] = nil
        controlClient.send(.applySettings(remoteSettings(for: selectedServiceID)))
    }

    func currentCameraSourceAspectRatio(fallback: CGFloat = SceneLayout.cameraAspectRatio) -> CGFloat {
        currentCameraSourceAspectRatio(settings: readSettings(), fallback: fallback)
    }

    private func currentCameraSourceAspectRatio(
        settings: RecordingSettings,
        fallback: CGFloat = SceneLayout.cameraAspectRatio
    ) -> CGFloat {
        guard let selectedServiceID = RemoteCameraProviderID.serviceID(from: settings.selectedCameraID),
              let capabilities = sessionState.capabilities[selectedServiceID] else {
            return fallback
        }

        let remoteSettings = remoteSettings(for: selectedServiceID)
        let lensCapabilities = capabilities.capabilities(for: remoteSettings.lens)
        let selectableFormats = RemoteCameraSettingsResolver.formats(
            lensCapabilities.supportedFormats,
            supportedBy: remoteSettings.captureProfileID,
            profiles: lensCapabilities.supportedCaptureProfiles
        )
        let formatCandidates = selectableFormats.isEmpty ? lensCapabilities.supportedFormats : selectableFormats
        guard let format = formatCandidates.first(where: { $0.id == remoteSettings.formatID })
            ?? formatCandidates.first else {
            return fallback
        }

        return CGFloat(RemoteCameraSettingsResolver.aspectRatio(
            format: format,
            rotationDegrees: remoteSettings.rotationDegrees
        ))
    }

    private func commitSettings(
        _ remoteSettings: RemoteCameraSettings,
        serviceID selectedServiceID: String,
        sendImmediately: Bool = false
    ) {
        var settings = readSettings()
        settings.remoteCameraSettingsByServiceID[selectedServiceID] = remoteSettings
        suppressPreview(serviceID: selectedServiceID, message: "Updating iPhone camera...")
        refreshSelectedScenePresetLayoutIfNeeded(settings: &settings)
        saveSettings(settings)
        sessionState.updateTelemetrySettings(for: selectedServiceID, activeSettings: remoteSettings)
        if sendImmediately {
            settingsSendTasks[selectedServiceID]?.cancel()
            settingsSendTasks[selectedServiceID] = nil
            controlClient.send(.applySettings(remoteSettings))
        } else {
            scheduleSettingsSend(remoteSettings, serviceID: selectedServiceID)
        }
        onCameraConfigurationChanged?()
    }

    func refreshSelectedScenePresetLayoutIfNeeded(settings: inout RecordingSettings) {
        guard let preset = settings.selectedScenePreset,
              preset.supports(settings.layout) else {
            return
        }
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: currentCameraSourceAspectRatio(settings: settings)
        ).withCameraSide(settings.sceneLayout.cameraSide)
    }

    private func scheduleSettingsSend(_ remoteSettings: RemoteCameraSettings, serviceID: String) {
        settingsSendTasks[serviceID]?.cancel()
        settingsSendTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: self?.settingsSendDelay ?? .milliseconds(150))
            await MainActor.run { [weak self] in
                guard let self,
                      !Task.isCancelled,
                      self.readSettings().selectedCameraID == RemoteCameraProviderID.make(for: serviceID) else {
                    return
                }
                self.settingsSendTasks[serviceID] = nil
                self.controlClient.send(.applySettings(remoteSettings))
            }
        }
    }

    func remoteSettings(for selectedServiceID: String) -> RemoteCameraSettings {
        let settings = readSettings()
        let activeTelemetry = sessionState.telemetry[selectedServiceID]
        return normalizedSettings(
            settings.remoteCameraSettingsByServiceID[selectedServiceID]
                ?? activeTelemetry?.activeSettings
                ?? RemoteCameraSettings(),
            for: selectedServiceID
        )
    }

    private func normalizedSettings(
        _ proposedSettings: RemoteCameraSettings,
        for selectedServiceID: String
    ) -> RemoteCameraSettings {
        RemoteCameraSettingsResolver.normalized(
            proposedSettings,
            capabilities: sessionState.capabilities[selectedServiceID],
            preferredFrameRate: readSettings().framesPerSecond
        )
    }

    func mergeAutomaticRotationTelemetry(
        _ telemetry: RemoteCameraTelemetry,
        serviceID: String,
        settings: inout RecordingSettings
    ) -> (telemetry: RemoteCameraTelemetry, didUpdateSettings: Bool) {
        let hadSavedSettings = settings.remoteCameraSettingsByServiceID[serviceID] != nil
        var savedSettings = settings.remoteCameraSettingsByServiceID[serviceID] ?? telemetry.activeSettings
        guard savedSettings.usesAutomaticRotation,
              telemetry.activeSettings.usesAutomaticRotation else {
            return (telemetry, false)
        }
        guard telemetry.phase == .idle || telemetry.phase == .preparing else {
            return (telemetry, false)
        }

        let rotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(telemetry.activeSettings.rotationDegrees)
        guard !hadSavedSettings || savedSettings.rotationDegrees != rotationDegrees else {
            return (telemetry, false)
        }

        savedSettings.rotationDegrees = rotationDegrees
        settings.remoteCameraSettingsByServiceID[serviceID] = savedSettings
        if settings.selectedScenePreset?.supports(settings.layout) == true {
            refreshSelectedScenePresetLayoutIfNeeded(settings: &settings)
        }

        var mergedTelemetry = telemetry
        mergedTelemetry.activeSettings = savedSettings
        return (mergedTelemetry, true)
    }

    func suppressPreview(serviceID: String, message: String) {
        previewSuppressedUntil[serviceID] = Date().addingTimeInterval(1.25)
        onPreviewReset?(message)
    }

    func isPreviewSuppressed(serviceID: String) -> Bool {
        guard let suppressedUntil = previewSuppressedUntil[serviceID] else {
            return false
        }
        if Date() < suppressedUntil {
            return true
        }
        previewSuppressedUntil.removeValue(forKey: serviceID)
        return false
    }
}
