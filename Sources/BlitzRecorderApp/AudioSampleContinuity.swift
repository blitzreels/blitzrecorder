import CoreMedia

/// Follows the timestamps of one audio source's samples and reports where they jump. The audio file output hides a
/// jump: it joins the samples on both sides, so everything after a lost stretch plays early against the video.
struct AudioSampleContinuity {
    static let toleratedJumpSeconds = 0.05

    struct Sample {
        let start: CMTime
        let duration: CMTime
    }

    struct Jump: Equatable {
        /// Positive when samples are missing, negative when they overlap.
        let seconds: Double
        /// Seconds of audio received before the jump, which is where it sits in the recorded file.
        let sourceSeconds: Double
    }

    private var expectedStart = CMTime.invalid
    private(set) var sourceSeconds = 0.0

    mutating func observe(_ sample: Sample) -> Jump? {
        guard sample.start.isNumeric, sample.duration.isNumeric, sample.duration.seconds > 0 else { return nil }
        defer {
            expectedStart = CMTimeAdd(sample.start, sample.duration)
            sourceSeconds += sample.duration.seconds
        }
        guard expectedStart.isNumeric else { return nil }
        let jump = CMTimeSubtract(sample.start, expectedStart).seconds
        guard abs(jump) > Self.toleratedJumpSeconds else { return nil }
        return Jump(seconds: jump, sourceSeconds: sourceSeconds)
    }

    /// A pause leaves a deliberate hole in the timestamps, so the next sample starts a new run.
    mutating func restart() {
        expectedStart = .invalid
    }
}
