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
            dropMicrophoneTrackUsedAsMainMicrophone()
            return
        }
        if let id, (committedRecordingSettings ?? settings).recordedExtraMicrophoneIDs.contains(id) {
            onMessage?("That microphone is already recording on its own track.")
            return
        }
        guard settings.enabledSources.contains(.microphone) else {
            studio.applyIdleMicrophone(id: id)
            return
        }
        let device = id.flatMap { MicrophoneDeviceSelection.microphone(id: $0) }
            ?? MicrophoneDeviceSelection.fallbackMicrophone(.init(settings: settings, excludedIDs: []))
        guard let device else {
            onMessage?("Microphone unavailable. Recording continues with the current microphone.")
            return
        }
        Task {
            do {
                try await takeRecording.switchMicrophone(to: device.uniqueID)
                guard state == .recording || state == .paused else { return }
                settings.selectedMicrophoneID = id
                settings.selectedMicrophoneName = MicrophoneDeviceSelection.preferredName(id: id)
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
        CaptureDeviceCatalog.microphoneName(settings: settings)
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
        returnToPreferredMicrophone(device)
        addConnectedCameraAsAngle(device)
        if actions.notifyCamera {
            onCameraConfigurationChanged?()
        }
    }

    /// A camera plugged in while idle becomes the next angle, so its scenes appear without another step.
    /// Desk View is skipped: it is a crop of an iPhone camera, not another angle.
    private func addConnectedCameraAsAngle(_ device: AVCaptureDevice) {
        guard state == .idle,
              device.hasMediaType(.video),
              device.deviceType != .deskViewCamera,
              device.uniqueID != mainLocalCameraDeviceID,
              !settings.extraCameraAngleIDs.contains(device.uniqueID) else { return }
        addCameraAngle(deviceID: device.uniqueID)
        let name = NumberedSourceTracks.cameraAngles.displayName(index: settings.extraCameraAngleIDs.count - 1)
        onMessage?("\(device.localizedName) is \(name). Its scenes are in the strip, with Two Cameras.")
    }

    func handleCaptureDeviceDisconnected(_ device: AVCaptureDevice) {
        if state == .recording || state == .paused,
           let index = (committedRecordingSettings ?? settings).recordedExtraMicrophoneIDs.firstIndex(of: device.uniqueID) {
            let name = NumberedSourceTracks.microphones.displayName(index: index + 1)
            Task { await takeRecording.stopMicrophoneTrack(deviceID: device.uniqueID) }
            onMessage?("\(name) was unplugged. What it recorded so far is kept.")
        }
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
        let extraMicrophones = (committedRecordingSettings ?? settings).recordedExtraMicrophoneIDs
        guard let fallback = MicrophoneDeviceSelection.fallbackMicrophone(.init(
            settings: committedRecordingSettings ?? settings,
            excludedIDs: Set(extraMicrophones + [disconnectedDevice.uniqueID])
        )) else {
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
                onMessage?(RecordingStopCopy.microphoneSwitched(fallback.localizedName))
            } catch {
                handleActiveCaptureFailure(ActiveCaptureFailure(source: .microphone, error: error))
            }
        }
    }

    /// Switches a running take back to the preferred microphone when it is plugged in again.
    func returnToPreferredMicrophone(_ device: AVCaptureDevice) {
        guard state == .recording || state == .paused,
              settings.enabledSources.contains(.microphone),
              device.uniqueID == settings.selectedMicrophoneID,
              activeMicrophoneDeviceID != device.uniqueID else { return }
        Task {
            do {
                try await takeRecording.switchMicrophone(to: device.uniqueID)
                guard state == .recording || state == .paused else { return }
                activeMicrophoneDeviceID = device.uniqueID
                onMessage?(RecordingStopCopy.microphoneReturned(device.localizedName))
            } catch {
                onMessage?(
                    "\(device.localizedName) is back, but switching to it failed. Recording continues with the current microphone: "
                        + error.recorderFailureDescription
                )
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
            if state == .idle {
                microphoneTracks.start(deviceIDs: settings.recordedExtraMicrophoneIDs, settings: settings)
            }
        } else {
            microphoneTracks.stop()
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
        microphoneTracks.stop()
        try? await systemAudioLevelMonitor.stop()
    }

    func prepareAudioLevelMonitoringForRecording() async {
        microphoneLevelMonitor.stop()
        microphoneTracks.stop()
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
