import Foundation

@MainActor
final class RecordingElapsedClock {
    var onElapsedSecondsChanged: ((Int) -> Void)?

    private var elapsedTimer: Timer?
    private var elapsedAccumulatedSeconds: TimeInterval = 0
    private var currentRecordingSegmentStartedAt: Date?

    deinit {
        elapsedTimer?.invalidate()
    }

    func applyState(_ newState: RecordingState, previousState: RecordingState) {
        switch newState {
        case .starting:
            reset()
        case .recording:
            if previousState == .idle || previousState == .starting || previousState == .finishing {
                reset()
            }
            currentRecordingSegmentStartedAt = Date()
            publishElapsedSeconds()
            startTimer()
        case .paused:
            publishElapsedSeconds()
            commitCurrentRecordingSegment()
            stopTimer()
        case .finishing:
            publishElapsedSeconds()
            commitCurrentRecordingSegment()
            stopTimer()
        case .idle:
            reset()
        }
    }

    func stop() {
        stopTimer()
    }

    private func reset() {
        stopTimer()
        elapsedAccumulatedSeconds = 0
        currentRecordingSegmentStartedAt = nil
        onElapsedSecondsChanged?(0)
    }

    private func startTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.publishElapsedSeconds()
            }
        }
    }

    private func stopTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func publishElapsedSeconds() {
        let currentSegmentSeconds: TimeInterval
        if let currentRecordingSegmentStartedAt {
            currentSegmentSeconds = Date().timeIntervalSince(currentRecordingSegmentStartedAt)
        } else {
            currentSegmentSeconds = 0
        }
        onElapsedSecondsChanged?(Int((elapsedAccumulatedSeconds + currentSegmentSeconds).rounded(.down)))
    }

    private func commitCurrentRecordingSegment() {
        guard let currentRecordingSegmentStartedAt else { return }
        elapsedAccumulatedSeconds += Date().timeIntervalSince(currentRecordingSegmentStartedAt)
        self.currentRecordingSegmentStartedAt = nil
        onElapsedSecondsChanged?(Int(elapsedAccumulatedSeconds.rounded(.down)))
    }
}
