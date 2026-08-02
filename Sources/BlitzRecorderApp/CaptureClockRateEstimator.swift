import CoreMedia
import Foundation

struct CaptureClockRateObservation {
    let sampleDuration: CMTime
    let masterTime: CMTime
}

struct CaptureClockRateMeasurement: Equatable {
    let sourceDuration: CMTime
    let masterDuration: CMTime

    var masterTimePerSourceTime: Double {
        guard sourceDuration.isValid,
              masterDuration.isValid,
              sourceDuration.seconds.isFinite,
              masterDuration.seconds.isFinite,
              sourceDuration.seconds > 0,
              masterDuration.seconds > 0 else {
            return 1
        }
        return masterDuration.seconds / sourceDuration.seconds
    }

    var accumulatedDrift: CMTime {
        CMTimeSubtract(masterDuration, sourceDuration)
    }
}

struct CaptureClockRateEstimator {
    private var sourceDurationSeconds = 0.0
    private var completedMasterDurationSeconds = 0.0
    private var currentSegmentMasterSpanSeconds = 0.0
    private var currentSegmentLastSampleDurationSeconds = 0.0
    private var lastMasterTime: CMTime?
    private var isPaused = false

    var measurement: CaptureClockRateMeasurement? {
        let masterDurationSeconds = completedMasterDurationSeconds
            + currentSegmentMasterSpanSeconds
            + currentSegmentLastSampleDurationSeconds
        guard sourceDurationSeconds > 0,
              masterDurationSeconds > 0 else {
            return nil
        }
        return CaptureClockRateMeasurement(
            sourceDuration: CMTime(seconds: sourceDurationSeconds, preferredTimescale: 1_000_000_000),
            masterDuration: CMTime(seconds: masterDurationSeconds, preferredTimescale: 1_000_000_000)
        )
    }

    mutating func observe(_ observation: CaptureClockRateObservation) {
        guard !isPaused,
              observation.sampleDuration.isValid,
              observation.masterTime.isValid else {
            return
        }
        let sampleDurationSeconds = observation.sampleDuration.seconds
        guard sampleDurationSeconds.isFinite,
              sampleDurationSeconds > 0 else {
            return
        }

        if let lastMasterTime {
            let masterDeltaSeconds = CMTimeSubtract(observation.masterTime, lastMasterTime).seconds
            if masterDeltaSeconds.isFinite, masterDeltaSeconds > 0 {
                currentSegmentMasterSpanSeconds += masterDeltaSeconds
            }
        }

        sourceDurationSeconds += sampleDurationSeconds
        currentSegmentLastSampleDurationSeconds = sampleDurationSeconds
        lastMasterTime = observation.masterTime
    }

    mutating func pause() {
        guard !isPaused else { return }
        finishCurrentSegment()
        isPaused = true
    }

    mutating func resume() {
        guard isPaused else { return }
        isPaused = false
    }

    mutating func reset() {
        self = CaptureClockRateEstimator()
    }

    private mutating func finishCurrentSegment() {
        completedMasterDurationSeconds += currentSegmentMasterSpanSeconds
            + currentSegmentLastSampleDurationSeconds
        currentSegmentMasterSpanSeconds = 0
        currentSegmentLastSampleDurationSeconds = 0
        lastMasterTime = nil
    }
}
