import BlitzRecorderCore
import Foundation

enum RemoteCameraControlsCopy {
    static func colorModeLabel(_ mode: RemoteCameraColorMode) -> String {
        switch mode {
        case .standard:
            return "Standard"
        case .appleLog:
            return "Log"
        case .appleLog2:
            return "Log 2"
        }
    }

    static func colorModeHelpText(_ mode: RemoteCameraColorMode) -> String {
        switch mode {
        case .standard:
            return "The normal iPhone video color pipeline."
        case .appleLog:
            return "Flat Apple Log ProRes for grading. Preview LUT is not applied yet."
        case .appleLog2:
            return "Apple Log 2 ProRes for newer iPhones. Preview LUT is not applied yet."
        }
    }

    static func captureProfileLabel(_ profileID: RemoteCameraCaptureProfileID) -> String {
        switch profileID {
        case .automatic:
            return "Best"
        case .highEfficiency:
            return "HEVC"
        case .proRes422:
            return "ProRes"
        }
    }

    static func captureProfileHelpText(_ profileID: RemoteCameraCaptureProfileID) -> String {
        switch profileID {
        case .automatic:
            return "Recommended. The iPhone chooses the best recording format."
        case .highEfficiency:
            return "High-efficiency iPhone quality. Required for Cinematic."
        case .proRes422:
            return "Very large ProRes files for editing. Not Cinematic mode."
        }
    }

    static func focusModeHelpText(_ mode: RemoteCameraFocusMode) -> String {
        switch mode {
        case .continuousAuto:
            return "Auto keeps the subject sharp as it moves."
        case .locked:
            return "Locked keeps the current focus and stops hunting."
        case .manual:
            return "Manual lets you set the focus distance yourself."
        }
    }

    static func exposureModeHelpText(_ mode: RemoteCameraExposureMode) -> String {
        switch mode {
        case .continuousAuto:
            return "Auto lets the iPhone adjust to brighter or darker scenes."
        case .locked:
            return "Locked keeps the current light level from changing."
        case .manual:
            return "Manual gives you ISO and shutter controls."
        }
    }

    static func whiteBalanceModeHelpText(_ mode: RemoteCameraWhiteBalanceMode) -> String {
        switch mode {
        case .continuousAuto:
            return "Auto keeps colors natural as the room light changes."
        case .locked:
            return "Locked stops colors from shifting during a take."
        case .manual:
            return "Manual lets you set warmth and tint yourself."
        }
    }

    static func stabilizationModeHelpText(_ mode: RemoteCameraStabilizationMode) -> String {
        switch mode {
        case .off:
            return "Off records without extra smoothing."
        case .standard:
            return "Standard smooths small hand movements."
        case .cinematic:
            return "Strong smoothing reduces bigger hand movements and may crop the image."
        case .cinematicExtendedEnhanced:
            return "Enhanced strong smoothing follows Apple's Cinematic recording path and may crop the image."
        case .auto:
            return "Auto lets the iPhone choose the best smoothing."
        }
    }

    static func stabilizationModeLabel(_ mode: RemoteCameraStabilizationMode) -> String {
        switch mode {
        case .off:
            return "Off"
        case .standard:
            return "Normal"
        case .cinematic:
            return "Strong"
        case .cinematicExtendedEnhanced:
            return "Enhanced"
        case .auto:
            return "Auto"
        }
    }

    static func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0s" }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded()))"
        }
        return String(format: "%.2fs", seconds)
    }
}
