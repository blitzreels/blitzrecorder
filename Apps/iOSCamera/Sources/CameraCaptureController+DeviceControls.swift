import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation

@MainActor
extension CameraCaptureController {
    @discardableResult
    func setZoomFactor(_ zoomFactor: CGFloat) async -> CGFloat {
        guard let activeDevice else { return zoomFactor }
        let result = await runOnSessionQueue {
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                let clamped = min(max(zoomFactor, activeDevice.minAvailableVideoZoomFactor), activeDevice.maxAvailableVideoZoomFactor)
                guard abs(activeDevice.videoZoomFactor - clamped) > 0.0001 else {
                    return (activeDevice.videoZoomFactor, true)
                }
                activeDevice.videoZoomFactor = clamped
                return (activeDevice.videoZoomFactor, true)
            } catch {
                return (activeDevice.videoZoomFactor, false)
            }
        }
        if !result.1 {
            statusMessage = "Zoom not available"
        }
        return result.0
    }

    func currentZoomFactor() async -> CGFloat {
        guard let activeDevice else { return 1 }
        return await runOnSessionQueue {
            activeDevice.videoZoomFactor
        }
    }

    @discardableResult
    func setTorchEnabled(_ isEnabled: Bool) async -> Bool {
        guard let activeDevice else {
            return false
        }
        guard activeDevice.hasTorch, activeDevice.isTorchAvailable else {
            if isEnabled {
                statusMessage = "Light not available"
            }
            return false
        }

        let result = await runOnSessionQueue {
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                if isEnabled {
                    try activeDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    activeDevice.torchMode = .off
                }
                return (activeDevice.torchMode == .on, true)
            } catch {
                return (activeDevice.torchMode == .on, false)
            }
        }
        if !result.1 {
            statusMessage = "Light not available"
        }
        return result.0
    }

    func currentTorchEnabled() async -> Bool {
        guard let activeDevice else { return false }
        return await runOnSessionQueue {
            activeDevice.torchMode == .on
        }
    }

    @discardableResult
    func setRotationDegrees(_ degrees: Int) async -> Int {
        let requestedRotation = RemoteCameraSettings.normalizedRotationDegrees(degrees)
        let supportedRotationDegrees = capabilities?.supportedRotationDegrees ?? [0, 90, 180, 270]
        let rotation = supportedRotationDegrees.contains(requestedRotation)
            ? requestedRotation
            : supportedRotationDegrees.first ?? requestedRotation
        await applyRotation(degrees: rotation)
        activeSettings.rotationDegrees = rotation
        return rotation
    }

    func configureActiveDevice(_ body: @escaping (AVCaptureDevice) -> Void) async -> Bool? {
        guard let activeDevice else { return nil }
        return await runOnSessionQueue { () -> Bool in
            do {
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                body(activeDevice)
                return true
            } catch {
                return false
            }
        }
    }

    func applyFocus(_ settings: RemoteCameraSettings) async {
        let applied = await configureActiveDevice { activeDevice in
            switch settings.focusMode {
            case .continuousAuto:
                if activeDevice.isFocusModeSupported(.continuousAutoFocus) {
                    activeDevice.focusMode = .continuousAutoFocus
                }
            case .locked:
                if activeDevice.isFocusModeSupported(.locked) {
                    activeDevice.focusMode = .locked
                }
            case .manual:
                if activeDevice.isLockingFocusWithCustomLensPositionSupported {
                    activeDevice.setFocusModeLocked(
                        lensPosition: Float(min(1, max(0, settings.focusPosition))),
                        completionHandler: nil
                    )
                }
            }
        }
        if applied == false {
            statusMessage = "Focus not available"
        }
    }

    func applyExposure(_ settings: RemoteCameraSettings) async {
        let applied = await configureActiveDevice { activeDevice in
            switch settings.exposureMode {
            case .continuousAuto:
                if activeDevice.isExposureModeSupported(.continuousAutoExposure) {
                    activeDevice.exposureMode = .continuousAutoExposure
                }
                Self.applyExposureTargetBias(settings.exposureBias, to: activeDevice)
            case .locked:
                Self.applyExposureTargetBias(settings.exposureBias, to: activeDevice)
                if activeDevice.isExposureModeSupported(.locked) {
                    activeDevice.exposureMode = .locked
                }
            case .manual:
                Self.applyExposureTargetBias(settings.exposureBias, to: activeDevice)
                if activeDevice.isExposureModeSupported(.custom) {
                    let iso = Float(min(
                        max(settings.iso ?? Double(activeDevice.iso), Double(activeDevice.activeFormat.minISO)),
                        Double(activeDevice.activeFormat.maxISO)
                    ))
                    let defaultDuration = CMTimeGetSeconds(activeDevice.exposureDuration)
                    let minDuration = CMTimeGetSeconds(activeDevice.activeFormat.minExposureDuration)
                    let maxDuration = CMTimeGetSeconds(activeDevice.activeFormat.maxExposureDuration)
                    let seconds = min(max(settings.shutterDurationSeconds ?? defaultDuration, minDuration), maxDuration)
                    activeDevice.setExposureModeCustom(
                        duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000),
                        iso: iso,
                        completionHandler: nil
                    )
                }
            }
        }
        if applied == false {
            statusMessage = "Exposure not available"
        }
    }

    private static func applyExposureTargetBias(_ exposureBias: Double, to device: AVCaptureDevice) {
        guard device.minExposureTargetBias < device.maxExposureTargetBias else { return }
        let bias = Float(min(
            Double(device.maxExposureTargetBias),
            max(Double(device.minExposureTargetBias), exposureBias)
        ))
        device.setExposureTargetBias(bias, completionHandler: nil)
    }

    func applyWhiteBalance(_ settings: RemoteCameraSettings) async {
        let applied = await configureActiveDevice { activeDevice in
            switch settings.whiteBalanceMode {
            case .continuousAuto:
                if activeDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    activeDevice.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            case .locked:
                if activeDevice.isWhiteBalanceModeSupported(.locked) {
                    activeDevice.whiteBalanceMode = .locked
                }
            case .manual:
                if activeDevice.isWhiteBalanceModeSupported(.locked) {
                    let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                        temperature: Float(settings.whiteBalanceTemperature),
                        tint: Float(settings.whiteBalanceTint)
                    )
                    let gains = Self.clampedWhiteBalanceGains(
                        activeDevice.deviceWhiteBalanceGains(for: values),
                        for: activeDevice
                    )
                    activeDevice.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                }
            }
        }
        if applied == false {
            statusMessage = "White balance not available"
        }
    }

    private static func clampedWhiteBalanceGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        let maximumGain = device.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(gains.redGain, 1), maximumGain),
            greenGain: min(max(gains.greenGain, 1), maximumGain),
            blueGain: min(max(gains.blueGain, 1), maximumGain)
        )
    }

    func applyStabilization(
        _ mode: RemoteCameraStabilizationMode
    ) async {
        let movieOutput = movieOutput
        let previewOutput = previewOutput
        let activeDevice = activeDevice
        await runOnSessionQueue {
            let avMode = Self.movieStabilizationMode(
                for: mode,
                activeFormat: activeDevice?.activeFormat
            )
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = avMode
            }
            if let connection = previewOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = avMode
            }
        }
    }

    private static func movieStabilizationMode(
        for mode: RemoteCameraStabilizationMode,
        activeFormat: AVCaptureDevice.Format?
    ) -> AVCaptureVideoStabilizationMode {
        guard let activeFormat else {
            return switch mode {
            case .off: .off
            case .standard: .standard
            case .cinematic: .cinematic
            case .cinematicExtendedEnhanced: .cinematicExtendedEnhanced
            case .auto: .auto
            }
        }
        switch mode {
        case .off:
            return .off
        case .standard:
            return activeFormat.isVideoStabilizationModeSupported(.standard) ? .standard : .off
        case .cinematic:
            if activeFormat.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
                return .cinematicExtendedEnhanced
            }
            if activeFormat.isVideoStabilizationModeSupported(.cinematic) {
                return .cinematic
            }
            return .off
        case .cinematicExtendedEnhanced:
            return activeFormat.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced)
                ? .cinematicExtendedEnhanced
                : .off
        case .auto:
            return activeFormat.isVideoStabilizationModeSupported(.auto) ? .auto : .off
        }
    }

    nonisolated static func remoteStabilizationMode(
        for mode: AVCaptureVideoStabilizationMode
    ) -> RemoteCameraStabilizationMode {
        switch mode {
        case .off:
            return .off
        case .standard:
            return .standard
        case .cinematic:
            return .cinematic
        case .auto:
            return .auto
        case .cinematicExtended:
            return .cinematic
        case .cinematicExtendedEnhanced:
            return .cinematicExtendedEnhanced
        default:
            return .off
        }
    }

    nonisolated static func stabilizationMatches(
        requested: RemoteCameraStabilizationMode,
        captured: RemoteCameraStabilizationMode
    ) -> Bool {
        switch requested {
        case .off:
            return captured == .off
        case .auto:
            return captured != .off
        case .standard:
            return captured == requested
        case .cinematic:
            return captured == .cinematic || captured == .cinematicExtendedEnhanced
        case .cinematicExtendedEnhanced:
            return captured == .cinematicExtendedEnhanced
        }
    }

    func applyRotation(degrees: Int) async {
        let rotation = Self.connectionAngle(forDeviceDegrees: degrees)
        let movieOutput = movieOutput
        let previewOutput = previewOutput
        await runOnSessionQueue {
            for connection in [movieOutput.connection(with: .video), previewOutput.connection(with: .video)].compactMap({ $0 }) {
                if connection.isVideoRotationAngleSupported(rotation) {
                    connection.videoRotationAngle = rotation
                }
            }
        }
    }

    /// Settings and the Mac describe how the iPhone is held (0 portrait, 90 landscape left, 180 upside down,
    /// 270 landscape right). The camera connection measures from the sensor, which sits 90° from portrait.
    /// The conversion is its own inverse.
    nonisolated static func connectionAngle(forDeviceDegrees degrees: Int) -> CGFloat {
        CGFloat(RemoteCameraSettings.normalizedRotationDegrees(90 - degrees))
    }

    nonisolated static func rotationDegrees(for connection: AVCaptureConnection) -> Int {
        RemoteCameraSettings.normalizedRotationDegrees(90 - Int(connection.videoRotationAngle.rounded()))
    }

    /// Follows gravity like Continuity Camera, so the picture stays level however the iPhone is mounted.
    func configureRotationCoordinator(for device: AVCaptureDevice?) {
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in
                self?.onLevelRotationChanged?()
            }
        }
    }

    /// How the iPhone is held, in settings degrees, from gravity. Nil before a camera is configured.
    var levelRotationDegrees: Int? {
        rotationCoordinator.map {
            RemoteCameraSettings.normalizedRotationDegrees(90 - Int($0.videoRotationAngleForHorizonLevelCapture.rounded()))
        }
    }
}
