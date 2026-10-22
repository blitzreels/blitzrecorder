import BlitzRecorderCore
import Foundation

extension CameraCompanionStore {
    var canRetryConnection: Bool {
        switch connectionState {
        case .degraded, .disconnected, .unavailable:
            return true
        case .discovering, .pairing, .connected:
            return false
        }
    }

    var connectionTitle: String {
        switch connectionState {
        case .discovering: return "Ready to connect"
        case .pairing: return "Connecting"
        case .connected: return pairedMacName.map { "Connected to \($0)" } ?? "Connected"
        case .degraded: return "Weak connection"
        case .disconnected: return "Not connected"
        case .unavailable: return "Not available"
        }
    }

    var elapsedLabel: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var cameraPresentation: CompanionCameraPresentation {
        CompanionCameraPresentation(
            isMacConnected: hasCompletedPairing,
            stage: cameraStage,
            macName: pairedMacName,
            captureFacts: captureFacts,
            warning: hasCompletedPairing || !isTakeInProgress
                ? camera.captureWarning
                : "Mac not connected. Recording continues on this iPhone.",
            waitingClipCount: pendingRecordingCount
        )
    }

    private var cameraStage: CompanionCameraPresentation.Stage {
        guard hasCompletedPairing || isTakeInProgress else {
            return .pairing(.init(code: pairingCode, connection: connectionState, step: pairingStep, macName: pairedMacName))
        }
        switch recordingPhase {
        case .idle: return .ready
        case .preparing: return .preparing
        case .recording: return .recording(elapsed: elapsedLabel)
        case .stopping: return .stopping
        case .transferring: return .sending(fraction: transferFraction)
        case .pendingImport: return .saved
        case .failed: return .failed(message: statusMessage)
        }
    }

    private var captureFacts: String? {
        guard camera.isPreviewRunning else { return nil }
        let settings = activeSettings
        let resolution = settings.formatID.flatMap(Self.resolutionLabel)
        return [
            settings.lens.displayName,
            resolution,
            "\(settings.frameRate) fps",
            settings.cinematicVideoEnabled ? "Cinematic" : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private static func resolutionLabel(_ formatID: String) -> String? {
        let sides = formatID.split(separator: "x").compactMap { Int($0) }
        guard sides.count == 2, let shortSide = sides.min() else { return nil }
        switch shortSide {
        case 2160...: return "4K"
        case 1080: return "1080p"
        case 720: return "720p"
        default: return "\(shortSide)p"
        }
    }
}
