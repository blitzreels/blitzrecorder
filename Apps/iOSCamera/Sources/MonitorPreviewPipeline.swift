import BlitzRecorderCore
import Foundation

@MainActor
final class MonitorPreviewPipeline {
    typealias EventSender = @MainActor (RemoteCameraEvent, @escaping @Sendable (Error?) -> Void) -> Bool
    typealias Clock = @MainActor () -> Date

    private struct FrameSample {
        var recordedAt: Date
        var wasDropped: Bool
    }

    private static let healthWindowSeconds: TimeInterval = 5
    private static let sendTimeoutSeconds: TimeInterval = 1

    private var recentFrameSamples: [FrameSample] = []
    private var sendInFlight = false
    private var inFlightSendID: UInt64?
    private var nextSendID: UInt64 = 0
    private var lastFrameSentAt: Date?
    private var isTransferActive = false
    private var lastCanPublish = true
    private let now: Clock

    var onHealthChanged: ((RemoteCameraPreviewHealth) -> Void)?
    var onPublishAvailabilityChanged: ((Bool) -> Void)?

    init(now: @escaping Clock = Date.init) {
        self.now = now
    }

    var health: RemoteCameraPreviewHealth {
        makeHealth(at: now())
    }

    func refreshHealth() {
        let now = now()
        pruneRecentFrameSamples(now: now)
        onHealthChanged?(makeHealth(at: now))
    }

    private func makeHealth(at now: Date) -> RemoteCameraPreviewHealth {
        let recentSamples = recentFrameSamples(in: now)
        return RemoteCameraPreviewHealth(
            framesSent: Int64(recentSamples.filter { !$0.wasDropped }.count),
            framesDropped: Int64(recentSamples.filter(\.wasDropped).count),
            lastFrameAgeSeconds: lastFrameSentAt.map { now.timeIntervalSince($0) },
            isTransferActive: isTransferActive
        )
    }

    func setTransferActive(_ active: Bool) {
        guard isTransferActive != active else { return }
        isTransferActive = active
        recentFrameSamples.removeAll()
        if active {
            lastFrameSentAt = nil
        }
        publishAvailabilityIfNeeded()
        refreshHealth()
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
        guard !isTransferActive else {
            return
        }

        guard !sendInFlight else {
            recordFrameDropped()
            return
        }

        nextSendID &+= 1
        let sendID = nextSendID
        sendInFlight = true
        inFlightSendID = sendID
        publishAvailabilityIfNeeded()
        guard send(event, { [weak self] error in
            Task { @MainActor in
                self?.finishSend(id: sendID, didSend: error == nil)
            }
        }) else {
            finishSend(id: sendID, didSend: false)
            return
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.sendTimeoutSeconds))
            self?.finishSend(id: sendID, didSend: false)
        }
    }

    private func finishSend(id: UInt64, didSend: Bool) {
        guard sendInFlight, inFlightSendID == id else { return }
        sendInFlight = false
        inFlightSendID = nil
        publishAvailabilityIfNeeded()
        if didSend {
            recordFrameSent()
        } else {
            recordFrameDropped()
        }
    }

    private func recordFrameSent() {
        let now = now()
        lastFrameSentAt = now
        appendFrameSample(wasDropped: false, recordedAt: now)
        onHealthChanged?(makeHealth(at: now))
    }

    private func recordFrameDropped() {
        let now = now()
        appendFrameSample(wasDropped: true, recordedAt: now)
        onHealthChanged?(makeHealth(at: now))
    }

    private func appendFrameSample(wasDropped: Bool, recordedAt: Date) {
        recentFrameSamples.append(FrameSample(recordedAt: recordedAt, wasDropped: wasDropped))
        pruneRecentFrameSamples(now: recordedAt)
    }

    private func recentFrameSamples(in now: Date) -> [FrameSample] {
        let cutoff = now.addingTimeInterval(-Self.healthWindowSeconds)
        return recentFrameSamples.filter { $0.recordedAt >= cutoff }
    }

    private func pruneRecentFrameSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.healthWindowSeconds)
        recentFrameSamples.removeAll { $0.recordedAt < cutoff }
    }

    private func publishAvailabilityIfNeeded() {
        let canPublish = !isTransferActive && !sendInFlight
        guard canPublish != lastCanPublish else { return }
        lastCanPublish = canPublish
        onPublishAvailabilityChanged?(canPublish)
    }
}
