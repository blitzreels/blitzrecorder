import BlitzRecorderCore
import Foundation

enum RemoteCameraReviewStatus {
    static func text(health: RemoteCameraPreviewHealth?) -> String {
        guard let health else {
            return "Waiting for iPhone video"
        }
        if health.isTransferActive {
            return "Importing iPhone video"
        }
        if health.isHealthy {
            return "Video looks good"
        }
        if health.isStale {
            return "iPhone live view stalled"
        }
        if health.isBlockedBeforeFirstFrame {
            return "iPhone live view blocked"
        }
        if health.isDroppingFrames {
            return "iPhone live view is dropping frames"
        }
        if health.isWaitingForFirstFrame {
            return "Waiting for iPhone video"
        }
        return "iPhone connected"
    }
}

enum RemoteCameraPreviewGeometry {
    static func displayAspectRatio(width: Int, height: Int, rotationDegrees: Int) -> CGFloat {
        guard width > 0, height > 0 else { return SceneLayout.cameraAspectRatio }
        return max(0.1, CGFloat(RemoteCameraSettingsResolver.aspectRatio(
            width: width,
            height: height,
            rotationDegrees: rotationDegrees
        )))
    }
}

struct RemoteCameraPreviewFrame: Equatable {
    let width: Int
    let height: Int
    let aspectRatio: CGFloat

    var size: (Int, Int) { (width, height) }

    init(width: Int, height: Int, rotationDegrees: Int) {
        self.width = width
        self.height = height
        aspectRatio = RemoteCameraPreviewGeometry.displayAspectRatio(
            width: width,
            height: height,
            rotationDegrees: rotationDegrees
        )
    }
}

enum RemoteCameraRotationPolicy {
    static func degrees(telemetry: RemoteCameraTelemetry?) -> Int {
        telemetry?.activeSettings.rotationDegrees ?? RemoteCameraSettings.defaultRotationDegrees
    }

    static func usesAutomaticRotation(telemetry: RemoteCameraTelemetry?) -> Bool {
        telemetry?.activeSettings.usesAutomaticRotation ?? true
    }

    static func supportedDegrees(capabilities: RemoteCameraCapabilities?) -> [Int] {
        let supported = capabilities?.supportedRotationDegrees
            .map(RemoteCameraSettings.normalizedRotationDegrees)
            ?? [0, 90, 180, 270]
        return Array(Set(supported)).sorted()
    }
}
