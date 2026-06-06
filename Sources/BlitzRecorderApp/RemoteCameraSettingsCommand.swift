import BlitzRecorderCore
import Foundation

enum RemoteCameraSettingsIntent: Equatable {
    case lens(RemoteCameraLens)
    case format(id: String?, frameRate: Int)
    case captureProfile(RemoteCameraCaptureProfileID)
    case colorMode(RemoteCameraColorMode)
    case cinematicVideoEnabled(Bool)
    case cinematicAperture(Double)
    case focusMode(RemoteCameraFocusMode)
    case focusPosition(Double)
    case exposureMode(RemoteCameraExposureMode)
    case exposureBias(Double)
    case resetExposureBias
    case iso(Double?)
    case shutterDuration(Double?)
    case whiteBalanceMode(RemoteCameraWhiteBalanceMode)
    case whiteBalance(temperature: Double, tint: Double)
    case stabilizationMode(RemoteCameraStabilizationMode)
    case automaticRotation(Bool)
    case rotationDegrees(Int)
    case resetImageSettings
    case resetAll(frameRate: Int)
}

struct RemoteCameraSettingsCommandResult: Equatable {
    var settings: RemoteCameraSettings
    var message: String?
    var didChange: Bool
}

enum RemoteCameraSettingsCommand {
    static func apply(
        _ intent: RemoteCameraSettingsIntent,
        to currentSettings: RemoteCameraSettings,
        capabilities: RemoteCameraCapabilities?,
        preferredFrameRate: Int
    ) -> RemoteCameraSettingsCommandResult {
        var remoteSettings = currentSettings
        let lensCapabilities = capabilities?.capabilities(for: remoteSettings.lens) ?? capabilities

        switch intent {
        case .lens(let lens):
            remoteSettings.lens = lens
            remoteSettings.zoomFactor = 1
            remoteSettings.torchEnabled = false
        case .format(let id, let frameRate):
            remoteSettings.formatID = id
            remoteSettings.frameRate = frameRate
        case .captureProfile(let profileID):
            if let profile = lensCapabilities?.supportedCaptureProfiles.first(where: { $0.id == profileID }),
               !profile.isAvailable {
                return RemoteCameraSettingsCommandResult(
                    settings: currentSettings,
                    message: profile.unavailableReason ?? "\(profile.displayName) is unavailable for this iPhone camera setting.",
                    didChange: false
                )
            }
            remoteSettings.captureProfileID = profileID
            if profileID != .proRes422 {
                remoteSettings.colorMode = .standard
            }
        case .colorMode(let colorMode):
            remoteSettings.colorMode = colorMode
            if colorMode != .standard {
                remoteSettings.captureProfileID = .proRes422
            }
        case .cinematicVideoEnabled(let enabled):
            remoteSettings.cinematicVideoEnabled = enabled
            if enabled {
                applyCinematicDefaults(to: &remoteSettings, lensCapabilities: lensCapabilities)
            }
            if enabled,
               let lensCapabilities,
               lensCapabilities.supportsCinematicVideo {
                remoteSettings.cinematicAperture = remoteSettings.cinematicAperture
                    ?? lensCapabilities.defaultCinematicAperture
                    ?? lensCapabilities.minimumCinematicAperture
            } else {
                remoteSettings.cinematicAperture = nil
            }
        case .cinematicAperture(let aperture):
            remoteSettings.cinematicVideoEnabled = true
            remoteSettings.cinematicAperture = aperture
            applyCinematicDefaults(to: &remoteSettings, lensCapabilities: lensCapabilities)
        case .focusMode(let mode):
            remoteSettings.focusMode = mode
        case .focusPosition(let position):
            remoteSettings.focusPosition = min(1, max(0, position))
        case .exposureMode(let mode):
            remoteSettings.exposureMode = mode
            if mode == .continuousAuto {
                remoteSettings.exposureBias = 0
                remoteSettings.iso = nil
                remoteSettings.shutterDurationSeconds = nil
            }
        case .exposureBias(let bias):
            remoteSettings.exposureBias = bias
        case .resetExposureBias:
            remoteSettings.exposureMode = .continuousAuto
            remoteSettings.exposureBias = 0
            remoteSettings.iso = nil
            remoteSettings.shutterDurationSeconds = nil
        case .iso(let iso):
            remoteSettings.iso = iso
        case .shutterDuration(let seconds):
            remoteSettings.shutterDurationSeconds = seconds
        case .whiteBalanceMode(let mode):
            remoteSettings.whiteBalanceMode = mode
            if mode == .continuousAuto {
                remoteSettings.whiteBalanceTemperature = 5_500
                remoteSettings.whiteBalanceTint = 0
            }
        case .whiteBalance(let temperature, let tint):
            remoteSettings.whiteBalanceTemperature = temperature
            remoteSettings.whiteBalanceTint = tint
        case .stabilizationMode(let mode):
            remoteSettings.stabilizationMode = mode
        case .automaticRotation(let enabled):
            remoteSettings.usesAutomaticRotation = enabled
        case .rotationDegrees(let degrees):
            remoteSettings.usesAutomaticRotation = false
            remoteSettings.rotationDegrees = RemoteCameraSettings.normalizedRotationDegrees(degrees)
        case .resetImageSettings:
            remoteSettings.focusMode = .continuousAuto
            remoteSettings.focusPosition = 0.5
            remoteSettings.exposureMode = .continuousAuto
            remoteSettings.exposureBias = 0
            remoteSettings.iso = nil
            remoteSettings.shutterDurationSeconds = nil
            remoteSettings.whiteBalanceMode = .continuousAuto
            remoteSettings.whiteBalanceTemperature = 5_500
            remoteSettings.whiteBalanceTint = 0
        case .resetAll(let frameRate):
            remoteSettings = RemoteCameraSettings(frameRate: frameRate)
        }

        let normalized = RemoteCameraSettingsResolver.normalized(
            remoteSettings,
            capabilities: capabilities,
            preferredFrameRate: preferredFrameRate
        )
        return RemoteCameraSettingsCommandResult(
            settings: normalized,
            message: nil,
            didChange: normalized != currentSettings
        )
    }

    private static func applyCinematicDefaults(
        to settings: inout RemoteCameraSettings,
        lensCapabilities: RemoteCameraCapabilities?
    ) {
        settings.colorMode = .standard
        settings.captureProfileID = .automatic
        if lensCapabilities?.supportedStabilizationModes.contains(.cinematic) == true {
            settings.stabilizationMode = .cinematic
        } else if lensCapabilities?.supportedStabilizationModes.contains(.auto) == true {
            settings.stabilizationMode = .auto
        }
    }
}
