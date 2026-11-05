import AVFoundation
import CoreMedia
import Foundation

struct LocalCameraDeliveryRequest {
    let device: AVCaptureDevice
    let pictureSize: CGSize
    let sourceSize: CGSize
    let fps: Int
}

struct LocalCameraDeliveryShortfall: Equatable {
    let cameraName: String
    let pictureSize: CGSize
    let bestSize: CGSize
    let sourceSize: CGSize

    var title: String {
        "Picture \(Self.label(pictureSize)) · below \(Self.label(bestSize))"
    }

    var detail: String {
        if sourceSize != pictureSize {
            return "Incoming frame: \(Self.label(sourceSize)). Usable picture after removing black bars: "
                + "\(Self.label(pictureSize)). Camera format available: \(Self.label(bestSize))."
        }
        return "Incoming frame: \(Self.label(sourceSize)). Camera format available: \(Self.label(bestSize)). "
            + "Open Camera controls to check the connection."
    }

    var recordingWarning: String {
        "\(cameraName) recorded at \(Self.label(pictureSize)), lower than its best \(Self.label(bestSize))."
    }

    private static func label(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }
}

enum LocalCameraDelivery {
    private static let acceptedAreaShare = 0.6

    static func shortfall(_ request: LocalCameraDeliveryRequest) -> LocalCameraDeliveryShortfall? {
        guard let best = LocalCameraSessionConfiguration.bestFormat(.init(
            device: request.device,
            fps: request.fps,
            sizeLimit: .recording
        )) else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
        let bestSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        let bestArea = bestSize.width * bestSize.height
        let pictureArea = request.pictureSize.width * request.pictureSize.height
        guard bestArea > 0, pictureArea / bestArea < acceptedAreaShare else { return nil }
        return LocalCameraDeliveryShortfall(
            cameraName: CameraOptionName.plain(request.device.localizedName),
            pictureSize: request.pictureSize,
            bestSize: bestSize,
            sourceSize: request.sourceSize
        )
    }
}


struct CameraDeliverySnapshot: Codable, Equatable, Sendable {
    let cameraName: String
    let sourceSize: CGSize
    let pictureSize: CGSize
    let activeFormatSize: CGSize
    let requestedFPS: Int
    let sampleTime: Double

    static func label(_ size: CGSize) -> String { "\(Int(size.width)) × \(Int(size.height))" }
}


struct CameraPreviewFormatRecovery {
    struct Request {
        let now: TimeInterval
        let sourceSize: CGSize
        let expectedSize: CGSize
    }

    private let deadline: TimeInterval
    private var nextCheck: TimeInterval
    private var attempts = 0

    init(startedAt: TimeInterval) {
        deadline = startedAt + 6
        nextCheck = startedAt + 0.5
    }

    func isComplete(at now: TimeInterval) -> Bool { now > deadline || attempts >= 3 }

    func isReady(at now: TimeInterval) -> Bool { now >= nextCheck && !isComplete(at: now) }

    mutating func shouldRestore(_ request: Request) -> Bool {
        guard isReady(at: request.now) else { return false }
        nextCheck = request.now + 1
        guard request.sourceSize != request.expectedSize else { return false }
        attempts += 1
        return true
    }
}
