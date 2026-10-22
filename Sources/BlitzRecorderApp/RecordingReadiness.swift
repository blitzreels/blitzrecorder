import Foundation

struct RecordingReadiness: Equatable {
    let isReady: Bool
    let title: String
    let detail: String
    let blockers: [PermissionBlocker]
    let statusLine: String

    func blocking(with blocker: PermissionBlocker, statusSuffix: String) -> RecordingReadiness {
        let statusLine = "\(self.statusLine) | \(statusSuffix)"
        return RecordingReadiness(
            isReady: false,
            title: title,
            detail: "Start disabled: \(statusLine)",
            blockers: blockers + [blocker],
            statusLine: statusLine
        )
    }

    func replacingScreenSourceBlockers(with blocker: PermissionBlocker) -> RecordingReadiness {
        RecordingReadiness(
            isReady: isReady,
            title: title,
            detail: detail,
            blockers: blockers.filter { $0.source != .screen && $0.source != .systemAudio },
            statusLine: statusLine
        ).blocking(with: blocker, statusSuffix: "Screen source: not selected")
    }
}

enum LocalCameraRuntimeState: Equatable {
    struct ReadinessRequest {
        let readiness: RecordingReadiness
        let settings: RecordingSettings
        let isRemoteCameraSelected: Bool
    }

    case unchecked
    case starting
    case waitingForDevice
    case ready
    case unavailable(String)

    func applying(_ request: ReadinessRequest) -> RecordingReadiness {
        guard request.settings.enabledSources.contains(.camera),
              !request.isRemoteCameraSelected else {
            return request.readiness
        }

        let blocker: PermissionBlocker
        switch self {
        case .unchecked, .ready:
            return request.readiness
        case .starting:
            blocker = PermissionBlocker(
                source: .camera,
                permission: "Camera availability",
                status: "starting",
                recovery: "Wait for the camera preview before recording."
            )
        case .waitingForDevice:
            blocker = PermissionBlocker(
                source: .camera,
                permission: "Camera availability",
                status: "waiting",
                recovery: "Bring your iPhone close and lock it, or plug in a camera. It connects on its own."
            )
        case .unavailable(let reason):
            blocker = PermissionBlocker(
                source: .camera,
                permission: "Camera availability",
                status: reason,
                recovery: "Choose another camera or close the app currently using it."
            )
        }

        return request.readiness.blocking(
            with: blocker,
            statusSuffix: "Camera: \(blocker.status)"
        )
    }
}

struct PermissionBlocker: Equatable {
    let source: CaptureSource
    let permission: String
    let status: String
    let recovery: String

    var sentence: String {
        if permission == "Screen & System Audio Recording" {
            switch source {
            case .screen:
                return "Screen source selected; full-capture access is inactive. \(recovery)"
            case .systemAudio:
                return "System Audio needs Screen Recording access. \(recovery)"
            case .camera, .microphone:
                break
            }
        }
        return "\(source.rawValue) blocked by \(permission): \(status). \(recovery)"
    }
}

extension Array where Element == PermissionBlocker {
    var shortSummary: String {
        if contains(where: { $0.permission == "Sources" }) {
            return "Pick a source to record"
        }
        if contains(where: { $0.permission == "Screen source" }) {
            return "Pick a screen or app to record"
        }
        if let cameraBlocker = first(where: { $0.permission == "Camera availability" }) {
            switch cameraBlocker.status {
            case "starting": return "Camera is starting"
            case "waiting": return "Waiting for a camera"
            default: return "Camera unavailable"
            }
        }
        if contains(where: { $0.source == .screen }),
           !contains(where: { $0.source == .systemAudio }) {
            return "Pick again or enable Screen Recording"
        }
        if contains(where: { $0.source == .systemAudio }),
           !contains(where: { $0.source == .screen }) {
            return "Mac audio needs Screen Recording"
        }
        var parts: [String] = []
        if contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            parts.append("Screen Recording")
        }
        if contains(where: { $0.permission == "Camera" }) { parts.append("Camera") }
        if contains(where: { $0.source == .microphone }) { parts.append("Microphone") }
        if parts.isEmpty {
            if contains(where: { $0.permission == "Remote iPhone" }) {
                return "Waiting for the iPhone camera to connect"
            }
            return "Permission needed to record"
        }
        return parts.count == 1 ? "\(parts[0]) permission needed" : "Permissions needed to record"
    }
}

struct PermissionRequestResult: Equatable {
    enum Status: Equatable {
        case granted
        case needsSettings
        case cancelled
    }

    let status: Status
    let message: String

    var isGranted: Bool {
        status == .granted
    }
}

enum RecordingPermissionSettingsPane {
    case screenCapture
    case accessibility
    case camera
    case microphone
}
