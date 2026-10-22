import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation

@MainActor
extension CameraCaptureController {
    func configureSystemPressureMonitoring(for device: AVCaptureDevice?) {
        systemPressureObservation?.invalidate()
        systemPressureObservation = nil
        setSystemPressureWarning(nil)
        guard let device else { return }
        systemPressureObservation = device.observe(
            \.systemPressureState,
            options: [.initial, .new]
        ) { [weak self] _, change in
            Task { @MainActor in
                self?.applySystemPressureState(change.newValue)
            }
        }
    }

    nonisolated static func enableLensSmudgeDetectionIfAvailable(_ device: AVCaptureDevice) {
        guard #available(iOS 26.0, *),
              device.activeFormat.isCameraLensSmudgeDetectionSupported,
              !device.isCameraLensSmudgeDetectionEnabled else { return }
        device.setCameraLensSmudgeDetectionEnabled(true, detectionInterval: CMTime(value: 30, timescale: 1))
    }

    func configureLensSmudgeMonitoring(for device: AVCaptureDevice?) {
        lensSmudgeObservation?.invalidate()
        lensSmudgeObservation = nil
        setLensSmudgeWarning(nil)
        guard #available(iOS 26.0, *), let device else { return }
        lensSmudgeObservation = device.observe(
            \.cameraLensSmudgeDetectionStatus,
            options: [.initial, .new]
        ) { [weak self] device, _ in
            let isSmudged = device.cameraLensSmudgeDetectionStatus == .smudged
            Task { @MainActor in
                self?.setLensSmudgeWarning(isSmudged ? "iPhone camera lens looks smudged; wipe it clean" : nil)
            }
        }
    }

    private func setLensSmudgeWarning(_ warning: String?) {
        guard lensSmudgeWarning != warning else { return }
        lensSmudgeWarning = warning
        publishCaptureWarningChanged()
    }

    private nonisolated static func systemPressureWarning(for state: AVCaptureDevice.SystemPressureState) -> String? {
        switch state.level {
        case .nominal:
            return nil
        case .fair:
            return "iPhone camera is warming; quality may drop"
        case .serious:
            return "iPhone is hot; camera quality may drop"
        case .critical:
            return "iPhone is too hot; recording may stop"
        case .shutdown:
            return "iPhone camera stopped due to heat"
        default:
            return "iPhone camera pressure is elevated"
        }
    }

    private nonisolated static func monitorPreviewLoadProfile(
        for state: AVCaptureDevice.SystemPressureState
    ) -> CameraMonitorPreviewLoadProfile {
        switch state.level {
        case .serious:
            return .reduced
        case .critical, .shutdown:
            return .minimal
        default:
            return .normal
        }
    }

    private func applySystemPressureState(_ state: AVCaptureDevice.SystemPressureState?) {
        setSystemPressureWarning(state.flatMap(Self.systemPressureWarning(for:)))
        systemPressurePreviewLoadProfile = state.map(Self.monitorPreviewLoadProfile(for:)) ?? .normal
        applyMonitorPreviewLoadProfile()
    }

    func adaptMonitorPreview(to health: RemoteCameraPreviewHealth) {
        if health.isTransferActive {
            networkPreviewLoadProfile = .minimal
        } else if health.isWaitingForFirstFrame {
            networkPreviewLoadProfile = .normal
        } else if health.isStale {
            networkPreviewLoadProfile = .minimal
        } else if health.isDroppingFrames {
            networkPreviewLoadProfile = .reduced
        } else if health.isHealthy {
            networkPreviewLoadProfile = .normal
        }
        applyMonitorPreviewLoadProfile()
    }

    private func applyMonitorPreviewLoadProfile() {
        let profile = max(systemPressurePreviewLoadProfile, networkPreviewLoadProfile)
        previewQueue.async {
            self.previewDelegate.setLoadProfile(profile)
        }
    }

    private func setSystemPressureWarning(_ warning: String?) {
        guard systemPressureWarning != warning else { return }
        systemPressureWarning = warning
        publishCaptureWarningChanged()
    }

    func publishCaptureWarningChanged() {
        let warning = captureWarning
        if captureSettingsAreLockedForRecording {
            activeRecordingWarningAccumulator.record(warning)
        }
        onCaptureWarningChanged?(warning)
    }
}
