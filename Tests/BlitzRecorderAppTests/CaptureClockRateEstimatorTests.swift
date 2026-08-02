import CoreMedia
import XCTest
@testable import BlitzRecorderApp

final class CaptureClockRateEstimatorTests: XCTestCase {
    func testMeasuresFortyFiveMinuteClockDrift() throws {
        var estimator = CaptureClockRateEstimator()
        let sampleDuration = 0.1
        let targetDrift = 3.6
        let packetCount = 27_000
        let rate = 1 + targetDrift / (Double(packetCount) * sampleDuration)
        var masterSeconds = 0.0

        for _ in 0..<packetCount {
            estimator.observe(.init(
                sampleDuration: CMTime(seconds: sampleDuration, preferredTimescale: 1_000_000_000),
                masterTime: CMTime(seconds: masterSeconds, preferredTimescale: 1_000_000_000)
            ))
            masterSeconds += sampleDuration * rate
        }

        let measurement = try XCTUnwrap(estimator.measurement)
        XCTAssertEqual(measurement.sourceDuration.seconds, 2_700, accuracy: 0.001)
        XCTAssertEqual(measurement.accumulatedDrift.seconds, targetDrift, accuracy: 0.002)
        XCTAssertEqual(measurement.masterTimePerSourceTime, rate, accuracy: 0.000001)
    }

    func testExcludesPausedWallClockTime() throws {
        var estimator = CaptureClockRateEstimator()
        var masterSeconds = 0.0

        for _ in 0..<100 {
            estimator.observe(observation(masterSeconds: masterSeconds))
            masterSeconds += 0.1
        }
        estimator.pause()
        masterSeconds += 30
        estimator.resume()
        for _ in 0..<100 {
            estimator.observe(observation(masterSeconds: masterSeconds))
            masterSeconds += 0.1
        }

        let measurement = try XCTUnwrap(estimator.measurement)
        XCTAssertEqual(measurement.sourceDuration.seconds, 20, accuracy: 0.001)
        XCTAssertEqual(measurement.masterDuration.seconds, 20, accuracy: 0.001)
    }

    private func observation(masterSeconds: Double) -> CaptureClockRateObservation {
        CaptureClockRateObservation(
            sampleDuration: CMTime(seconds: 0.1, preferredTimescale: 1_000_000_000),
            masterTime: CMTime(seconds: masterSeconds, preferredTimescale: 1_000_000_000)
        )
    }
}
