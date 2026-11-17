import CoreMedia

/// Keeps a video source's frames at their real capture time. A camera can stall and then carry on with
/// timestamps that run evenly from where they stopped, so every later frame is stamped earlier than it was
/// taken: the picture moves ahead of the sound and nothing in the file shows it. The time between a frame's
/// timestamp and its arrival is steady while capture is healthy; the shortest such time over a few frames rising
/// for good means the timestamps fell behind, and later frames are moved by that amount. The writer then holds
/// the previous frame across the hole, so the timeline stays real.
struct CaptureClockSlipDetector {
    static let windowFrames = 15
    static let toleratedSlipSeconds = 0.05

    struct Observation {
        let presentationTime: CMTime
        let arrivalTime: CMTime
    }

    struct Slip: Equatable {
        let seconds: Double
        /// Corrected timestamp of the first frame moved, on the capture clock.
        let presentationSeconds: Double
    }

    private(set) var correctionSeconds = 0.0
    private var baselineLag: Double?
    private var recentLags: [Double] = []

    mutating func observe(_ observation: Observation) -> Slip? {
        guard observation.presentationTime.isNumeric, observation.arrivalTime.isNumeric else { return nil }
        let presentation = observation.presentationTime.seconds + correctionSeconds
        recentLags.append(observation.arrivalTime.seconds - presentation)
        if recentLags.count > Self.windowFrames { recentLags.removeFirst() }
        guard recentLags.count == Self.windowFrames, let lowest = recentLags.min() else { return nil }
        guard let baselineLag, lowest >= baselineLag else {
            baselineLag = lowest
            return nil
        }
        let slip = lowest - baselineLag
        guard slip > Self.toleratedSlipSeconds else { return nil }
        correctionSeconds += slip
        recentLags.removeAll()
        return Slip(seconds: slip, presentationSeconds: presentation + slip)
    }

    struct Correction {
        let sampleBuffer: CMSampleBuffer
        let slip: Slip?
        let totalSeconds: Double

        func logLine(track: String) -> String? {
            slip.map { slip in
                String(format: "%@: frame timestamps fell %.3f s behind their arrival at %.3f s; later frames moved "
                    + "to their capture time (%.3f s in all)", track, slip.seconds, slip.presentationSeconds, totalSeconds)
            }
        }
    }

    /// Observes a captured frame and returns it at its corrected time.
    mutating func correct(_ observation: SampleObservation) -> Correction {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(observation.sampleBuffer)
        let slip = observe(.init(presentationTime: presentationTime, arrivalTime: observation.arrivalTime))
        guard correctionSeconds > 0, presentationTime.isNumeric,
              let moved = observation.sampleBuffer.retimed(toPresentationTime: CMTimeAdd(
                presentationTime, CMTime(seconds: correctionSeconds, preferredTimescale: 1_000_000_000)
              )) else {
            return Correction(sampleBuffer: observation.sampleBuffer, slip: slip, totalSeconds: correctionSeconds)
        }
        return Correction(sampleBuffer: moved, slip: slip, totalSeconds: correctionSeconds)
    }

    struct SampleObservation {
        let sampleBuffer: CMSampleBuffer
        let arrivalTime: CMTime
    }
}
