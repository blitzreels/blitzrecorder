import BlitzRecorderCore
import Foundation

@MainActor
final class MonitorPreviewPipeline {
    typealias EventSender = @MainActor (RemoteCameraEvent, @escaping @Sendable (Error?) -> Void) -> Bool
    typealias Clock = @MainActor () -> Date

    private var framesSent: Int64 = 0
    private var framesDropped: Int64 = 0
    private var sendInFlight = false
    private var lastFrameSentAt: Date?
    private var isTransferActive = false
    private let now: Clock

    var onHealthChanged: ((RemoteCameraPreviewHealth) -> Void)?

    init(now: @escaping Clock = Date.init) {
        self.now = now
    }

    var health: RemoteCameraPreviewHealth {
        RemoteCameraPreviewHealth(
            framesSent: framesSent,
            framesDropped: framesDropped,
            lastFrameAgeSeconds: lastFrameSentAt.map { now().timeIntervalSince($0) }
        )
    }

    func setTransferActive(_ active: Bool) {
        isTransferActive = active
    }

    func sendJPEGFrame(
        data: Data,
        width: Int,
        height: Int,
        using send: EventSender
    ) {
        publish(
            .monitorFrame(jpegData: data, width: width, height: height),
            using: send
        )
    }

    func sendVideoFrame(
        _ frame: RemoteCameraMonitorVideoFrame,
        using send: EventSender
    ) {
        publish(.monitorVideoFrame(frame), using: send)
    }

    func recordCaptureDroppedFrame() {
        recordFrameDropped()
    }

    private func publish(_ event: RemoteCameraEvent, using send: EventSender) {
        guard !sendInFlight, !isTransferActive else {
            recordFrameDropped()
            return
        }

        sendInFlight = true
        guard send(event, { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.sendInFlight = false
                if error != nil {
                    self.recordFrameDropped()
                }
            }
        }) else {
            sendInFlight = false
            recordFrameDropped()
            return
        }
        recordFrameSent()
    }

    private func recordFrameSent() {
        framesSent += 1
        lastFrameSentAt = now()
        onHealthChanged?(health)
    }

    private func recordFrameDropped() {
        framesDropped += 1
        onHealthChanged?(health)
    }
}
