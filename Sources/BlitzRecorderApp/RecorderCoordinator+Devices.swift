import os
import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
    func setSource(_ source: CaptureSource, enabled: Bool) {
        guard state == .idle || takeRecording.isUsingLiveCompositor else {
            onMessage?("Capture source visibility is locked while recording.")
            return
        }
        studio.setSourceVisibilityDuringLiveCompositor(source, enabled: enabled)
    }

    func uniqueOutputURL(_ url: URL) -> URL {
        takeFileStore.uniqueFileURL(url)
    }

    func setMicrophone(id: String?) {
        guard state == .recording || state == .paused else {
            studio.applyIdleMicrophone(id: id)
            return
        }
        guard settings.enabledSources.contains(.microphone) else {
            studio.applyIdleMicrophone(id: id)
            return
        }
        let device = id.flatMap { MicrophoneDeviceSelection.microphone(id: $0) }
            ?? MicrophoneDeviceSelection.fallbackMicrophone()
        guard let device else {
            onMessage?("Microphone unavailable. Recording continues with the current microphone.")
            return
        }
        Task {
            do {
                try await takeRecording.switchMicrophone(to: device.uniqueID)
                guard state == .recording || state == .paused else { return }
                settings.selectedMicrophoneID = id
                activeMicrophoneDeviceID = device.uniqueID
                persistSettings()
                onMessage?("Microphone switched to \(device.localizedName). Recording continues.")
            } catch {
                onMessage?(
                    "Could not switch microphone. Recording continues with the current microphone: "
                        + error.recorderFailureDescription
                )
            }
        }
    }

    func hasScreenCaptureAccess() -> Bool {
        permissionGate.hasScreenCaptureAccess
    }

    func recordingReadiness() -> RecordingReadiness {
        localCameraRuntimeState.applying(.init(
            readiness: RecordingStartGate.readiness(
                permission: permissionGate.readiness(for: settings),
                settings: settings,
                hasActiveScreenSourceSelection: hasActiveScreenSourceSelection,
                remoteBlocker: remoteCameraConnectionBlocker()
            ),
            settings: settings,
            isRemoteCameraSelected: isRemoteCameraSelected
        ))
    }

    func setLocalCameraRuntimeState(_ state: LocalCameraRuntimeState) {
        localCameraRuntimeState = state
    }

    func requestPermissionsForEnabledSources() async {
        let needsScreenRecordingGrant =
            (settings.enabledSources.contains(.screen)
                && !settings.usesPickedScreenContent)
            || settings.enabledSources.contains(.systemAudio)
        if needsScreenRecordingGrant {
            _ = await permissionGate.requestScreenCaptureAccess()
        }

        if settings.enabledSources.contains(.camera), !isRemoteCameraSelected {
            _ = await permissionGate.requestCameraAccess()
        }

        if settings.enabledSources.contains(.microphone) {
            _ = await permissionGate.requestMicrophoneAccess()
        }
    }

    func availableCameras() -> [SourceOption] {
        remoteCameraOptions() + CaptureDeviceCatalog.localCameraOptions()
    }

    func availableMicrophones() -> [SourceOption] {
        CaptureDeviceCatalog.microphoneOptions()
    }

    func selectedMicrophoneName() -> String {
        CaptureDeviceCatalog.microphoneName(selectedID: settings.selectedMicrophoneID)
    }

    func handleActiveMicrophoneCaptureFailure(_ error: Error) {
        handleActiveCaptureFailure(ActiveCaptureFailure(source: .microphone, error: error))
    }

    func handleActiveCaptureFailure(_ failure: ActiveCaptureFailure) {
        guard state == .recording || state == .paused else { return }
        let recordingSettings = committedRecordingSettings ?? settings
        let decision = CaptureFailureRecovery.decision(.init(
            source: failure.source,
            enabledSources: recordingSettings.enabledSources,
            usesLiveCompositor: takeRecording.isUsingLiveCompositor,
            usesRemoteCamera: isRemoteCameraSelected
        ))
        if decision == .continueWithBlackCamera {
            cameraRecorder.continueWithBlackFrames()
            let warning = CaptureFailureRecovery.blackCameraWarning
            if !activeCaptureWarnings.contains(warning) {
                activeCaptureWarnings.append(warning)
            }
            onMessage?(warning)
            return
        }
        stop()
        onRequestForeground?()
        onMessage?(RecordingStopCopy.captureFailed(source: failure.source, error: failure.error))
    }

    func noteActiveCaptureDevices(settings: RecordingSettings) {
        activeMicrophoneDeviceID = ActiveCaptureDeviceIDs.microphone(settings: settings)
        activeLocalCameraDeviceID = ActiveCaptureDeviceIDs.localCamera(settings: settings)
    }

    func clearActiveCaptureDevices() {
        activeMicrophoneDeviceID = nil
        activeLocalCameraDeviceID = nil
    }

    func handleCaptureDeviceConnected(_ device: AVCaptureDevice) {
        let actions = CaptureDeviceEvent.connected(
            hasAudio: device.hasMediaType(.audio),
            hasVideo: device.hasMediaType(.video),
            isIdle: state == .idle
        )
        if actions.refreshAudio {
            refreshAudioLevelMonitoring()
        }
        if actions.notifyCamera {
            onCameraConfigurationChanged?()
        }
    }

    func handleCaptureDeviceDisconnected(_ device: AVCaptureDevice) {
        let actions = CaptureDeviceEvent.disconnected(
            isActiveMicrophone: device.hasMediaType(.audio) && activeMicrophoneDeviceID == device.uniqueID,
            isActiveLocalCamera: device.hasMediaType(.video) && activeLocalCameraDeviceID == device.uniqueID,
            isIdle: state == .idle
        )
        if actions.recoverMicrophone {
            recoverDisconnectedMicrophone(device)
        }
        if actions.failCamera {
            handleActiveCaptureFailure(ActiveCaptureFailure(
                source: .camera,
                error: RecorderError.mediaWriteFailed("The selected camera disconnected.")
            ))
        }
        if actions.refreshIdleAudio {
            refreshAudioLevelMonitoring()
        }
    }

    func recoverDisconnectedMicrophone(_ disconnectedDevice: AVCaptureDevice) {
        guard state == .recording || state == .paused else { return }
        guard let fallback = MicrophoneDeviceSelection.fallbackMicrophone(
            excluding: disconnectedDevice.uniqueID
        ) else {
            handleActiveCaptureFailure(ActiveCaptureFailure(
                source: .microphone,
                error: RecorderError.microphoneUnavailable
            ))
            return
        }
        Task {
            do {
                try await takeRecording.switchMicrophone(to: fallback.uniqueID)
                guard state == .recording || state == .paused else { return }
                activeMicrophoneDeviceID = fallback.uniqueID
                settings.selectedMicrophoneID = nil
                persistSettings()
                onMessage?(RecordingStopCopy.microphoneSwitched(fallback.localizedName))
            } catch {
                handleActiveCaptureFailure(ActiveCaptureFailure(source: .microphone, error: error))
            }
        }
    }

    func refreshAudioLevelMonitoring() {
        guard state == .idle, idleCaptureResourcesEnabled else { return }
        Task {
            await configureAudioLevelMonitoring()
        }
    }

    func configureAudioLevelMonitoring() async {
        guard state != .idle || idleCaptureResourcesEnabled else {
            await stopAudioLevelMonitoring()
            return
        }
        if settings.enabledSources.contains(.microphone) {
            do {
                try microphoneLevelMonitor.start(settings: settings)
            } catch {
                microphoneLevelMonitor.stop()
            }
        } else {
            microphoneLevelMonitor.stop()
        }

        if settings.enabledSources.contains(.systemAudio) {
            let pickedScreenFilter = try? await resolvedScreenFilter(for: settings)
            guard pickedScreenFilter != nil else {
                try? await systemAudioLevelMonitor.stop()
                onAudioLevel?(.systemAudio, 0)
                return
            }
            guard state != .idle || idleCaptureResourcesEnabled else {
                await stopAudioLevelMonitoring()
                return
            }
            do {
                try await systemAudioLevelMonitor.start(.init(
                    settings: settings,
                    pickedScreenFilter: pickedScreenFilter
                ))
            } catch {
                try? await systemAudioLevelMonitor.stop()
            }
        } else {
            try? await systemAudioLevelMonitor.stop()
        }
        if state == .idle, !idleCaptureResourcesEnabled {
            await stopAudioLevelMonitoring()
        }
    }

    func stopAudioLevelMonitoring() async {
        microphoneLevelMonitor.stop()
        try? await systemAudioLevelMonitor.stop()
    }

    func prepareAudioLevelMonitoringForRecording() async {
        microphoneLevelMonitor.stop()
        guard settings.enabledSources.contains(.systemAudio) else {
            try? await systemAudioLevelMonitor.stop()
            return
        }
        do {
            if let stream = try systemAudioLevelMonitor.detachStreamForRecording() {
                systemAudioRecorder.adoptMonitoringStream(stream)
                return
            }
        } catch {
            try? await systemAudioLevelMonitor.stop()
        }
    }

    func startCaptureDeviceMonitoring() {
        captureDeviceMonitor.onConnected = { [weak self] device in
            self?.handleCaptureDeviceConnected(device)
        }
        captureDeviceMonitor.onDisconnected = { [weak self] device in
            self?.handleCaptureDeviceDisconnected(device)
        }
        captureDeviceMonitor.start()
    }
}
