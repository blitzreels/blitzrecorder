import AVFoundation
import BlitzRecorderCore
import CoreMedia

struct CameraCaptureSessionConfigurationPlan: Equatable {
    var lens: RemoteCameraLens
    var prefersCinematicDevice: Bool
    var resetsZoom: Bool = true
}

struct CameraCaptureSettingsRequestPlan: Equatable {
    var settings: RemoteCameraSettings
    var sessionConfiguration: CameraCaptureSessionConfigurationPlan?
}

struct CameraCaptureSettingsPlanner {
    let capabilityBuilder: RemoteCameraCaptureCapabilityBuilder

    func requestPlan(
        for settings: RemoteCameraSettings,
        isRecording: Bool,
        activeLens: RemoteCameraLens,
        activePrefersCinematicDevice: Bool
    ) -> CameraCaptureSettingsRequestPlan {
        var requestedSettings = settings
        guard !isRecording else {
            return CameraCaptureSettingsRequestPlan(settings: requestedSettings)
        }

        if requestedSettings.cinematicVideoEnabled,
           let cinematicLens = capabilityBuilder.preferredCinematicLens() {
            requestedSettings.lens = cinematicLens
        }

        if requestedSettings.cinematicVideoEnabled,
           requestedSettings.lens != activeLens || !activePrefersCinematicDevice {
            return CameraCaptureSettingsRequestPlan(
                settings: requestedSettings,
                sessionConfiguration: CameraCaptureSessionConfigurationPlan(
                    lens: requestedSettings.lens,
                    prefersCinematicDevice: true
                )
            )
        }

        if !requestedSettings.cinematicVideoEnabled,
           requestedSettings.lens != activeLens || activePrefersCinematicDevice {
            return CameraCaptureSettingsRequestPlan(
                settings: requestedSettings,
                sessionConfiguration: CameraCaptureSessionConfigurationPlan(
                    lens: requestedSettings.lens,
                    prefersCinematicDevice: false
                )
            )
        }

        return CameraCaptureSettingsRequestPlan(settings: requestedSettings)
    }

    func normalizedSettings(
        _ settings: RemoteCameraSettings,
        activeDevice: AVCaptureDevice?
    ) -> RemoteCameraSettings {
        guard let activeDevice else {
            return RemoteCameraSettingsResolver.normalized(
                settings,
                capabilities: nil,
                preferredFrameRate: settings.frameRate
            )
        }
        var normalizedSettings = RemoteCameraSettingsResolver.normalized(
            settings,
            capabilities: capabilityBuilder.makeCapabilities(activeDevice: activeDevice),
            preferredFrameRate: settings.frameRate
        )
        normalizedSettings = normalizedCinematicCaptureFormat(
            normalizedSettings,
            activeDevice: activeDevice
        )
        return normalizedSettings
    }

    func preserveActiveCaptureSettings(
        in settings: RemoteCameraSettings,
        activeLens: RemoteCameraLens,
        activeCaptureProfileID: RemoteCameraCaptureProfileID,
        activeCinematicVideoEnabled: Bool,
        activeCinematicAperture: Double?,
        activeDevice: AVCaptureDevice?
    ) -> RemoteCameraSettings {
        var preservedSettings = settings
        preservedSettings.lens = activeLens
        preservedSettings.captureProfileID = activeCaptureProfileID
        preservedSettings.cinematicVideoEnabled = activeCinematicVideoEnabled
        preservedSettings.cinematicAperture = activeCinematicAperture
        if let activeDevice {
            preservedSettings.formatID = Self.formatID(for: activeDevice.activeFormat)
            let frameRate = Self.activeFrameRate(for: activeDevice)
            if frameRate > 0 {
                preservedSettings.frameRate = frameRate
            }
        }
        return preservedSettings
    }

    func canApplyOnlyCinematicAperture(
        _ settings: RemoteCameraSettings,
        activeCinematicVideoEnabled: Bool,
        activeCinematicAperture: Double?,
        activeVideoInput: AVCaptureDeviceInput?
    ) -> Bool {
        guard #available(iOS 26.0, *),
              settings.cinematicVideoEnabled,
              activeCinematicVideoEnabled,
              !Self.cinematicAperturesMatch(settings.cinematicAperture, activeCinematicAperture),
              activeVideoInput?.isCinematicVideoCaptureEnabled == true else {
            return false
        }
        return true
    }

    static func cinematicAperturesMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs - rhs) < 0.001
        default:
            return false
        }
    }

    private func normalizedCinematicCaptureFormat(
        _ settings: RemoteCameraSettings,
        activeDevice: AVCaptureDevice
    ) -> RemoteCameraSettings {
        var normalizedSettings = settings
        guard normalizedSettings.cinematicVideoEnabled else {
            return normalizedSettings
        }
        normalizedSettings.colorMode = .standard
        let cinematic = capabilityBuilder.cinematicCapabilities(for: activeDevice)
        guard cinematic.supportsCinematicVideo else {
            normalizedSettings.cinematicVideoEnabled = false
            normalizedSettings.cinematicAperture = nil
            return normalizedSettings
        }
        let formats = capabilityBuilder.remoteFormats(for: activeDevice)
        let preferredFormatID = normalizedSettings.formatID ?? formats.first?.id
        guard let preferredFormatID,
              let cinematicFormat = RemoteCameraCaptureProfileResolver.captureFormat(
                for: normalizedSettings.captureProfileID,
                formatID: preferredFormatID,
                frameRate: normalizedSettings.frameRate,
                device: activeDevice,
                requiresCinematic: true
              ) ?? RemoteCameraCaptureProfileResolver.captureFormat(
                for: .automatic,
                formatID: preferredFormatID,
                frameRate: normalizedSettings.frameRate,
                device: activeDevice,
                requiresCinematic: true
              ) ?? RemoteCameraCaptureProfileResolver.preferredCinematicCaptureFormat(
                for: activeDevice,
                preferredFrameRate: normalizedSettings.frameRate
              ) else {
            normalizedSettings.cinematicVideoEnabled = false
            normalizedSettings.cinematicAperture = nil
            return normalizedSettings
        }
        normalizedSettings.captureProfileID = .automatic
        normalizedSettings.formatID = Self.formatID(for: cinematicFormat)
        let frameRates = capabilityBuilder.supportedRemoteFrameRates(for: [cinematicFormat])
        if !frameRates.contains(normalizedSettings.frameRate) {
            normalizedSettings.frameRate = frameRates.contains(30) ? 30 : (frameRates.first ?? 30)
        }
        return normalizedSettings
    }

    private static func formatID(for format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height)"
    }

    private static func activeFrameRate(for device: AVCaptureDevice) -> Int {
        let seconds = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(1, Int((1 / seconds).rounded()))
    }
}
