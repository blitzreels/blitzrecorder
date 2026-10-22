import CoreMedia
import Foundation

struct RecordingTimelineAnchor {
    private var timelineStartTime: CMTime?
    private var firstSampleTime: CMTime?

    mutating func reset(timelineStartTime: CMTime?) {
        self.timelineStartTime = timelineStartTime
        firstSampleTime = nil
    }

    mutating func observeFirstSample(_ sampleBuffer: CMSampleBuffer) {
        guard firstSampleTime == nil else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if presentationTime.isValid {
            firstSampleTime = presentationTime
        }
    }

    var offset: CMTime {
        guard let timelineStartTime,
              let firstSampleTime else { return .zero }
        let offset = CMTimeSubtract(firstSampleTime, timelineStartTime)
        guard offset.isValid,
              offset.seconds.isFinite,
              CMTimeCompare(offset, .zero) > 0 else { return .zero }
        return CMTimeConvertScale(offset, timescale: 600, method: .roundHalfAwayFromZero)
    }
}

final class AudioStartupGate: @unchecked Sendable {
    private let timeoutError: Error
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private(set) var hasProducedSample = false

    init(timeoutError: Error) {
        self.timeoutError = timeoutError
    }

    func reset() {
        hasProducedSample = false
    }

    func wait(on queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.hasProducedSample {
                    continuation.resume()
                    return
                }
                self.continuation = continuation
                self.timeoutTask?.cancel()
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    queue.async {
                        guard let self else { return }
                        self.complete(.failure(self.timeoutError))
                    }
                }
            }
        }
    }

    func complete(_ result: Result<Void, Error>) {
        if case .success = result {
            hasProducedSample = true
        }
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }
}
