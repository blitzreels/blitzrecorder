import BlitzRecorderCore
import Foundation

enum CameraDeviceStatus {
    static func phoneHeatLabel(for thermalState: ProcessInfo.ThermalState) -> String {
        switch thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Warm"
        case .serious, .critical:
            return "Needs a break"
        @unknown default:
            return "Unknown"
        }
    }

    static func freeStorageBytes() -> Int64? {
        guard let freeBytes = try? FileManager.default
            .attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber else {
            return nil
        }
        return freeBytes.int64Value
    }

    static func previewHealthLabel(for health: RemoteCameraPreviewHealth) -> String {
        if health.isTransferActive {
            return "Importing"
        } else if health.isStale {
            return "Stale"
        } else if health.isBlockedBeforeFirstFrame {
            return "Blocked"
        } else if health.isDroppingFrames {
            return "\(Int((health.droppedFrameRatio * 100).rounded()))% drop"
        } else if health.isWaitingForFirstFrame {
            return "Waiting"
        } else if health.isHealthy {
            return "\(health.framesSent) ok"
        } else {
            return "Connected"
        }
    }
}

enum CameraPreviewHealthTelemetryState: Equatable {
    case transferActive
    case waiting
    case stale
    case dropping
    case healthy

    init(health: RemoteCameraPreviewHealth) {
        if health.isTransferActive {
            self = .transferActive
        } else if health.isStale {
            self = .stale
        } else if health.isBlockedBeforeFirstFrame || health.isDroppingFrames {
            self = .dropping
        } else if health.isWaitingForFirstFrame {
            self = .waiting
        } else {
            self = .healthy
        }
    }
}
