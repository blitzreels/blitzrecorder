import AVFoundation
import XCTest

@testable import BlitzRecorderApp

final class EditorAudioWaveformTests: XCTestCase {
    func testDecoderPreservesSingleSampleTransientsInBothChannels() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<2 {
            for frame in 0..<48_000 { channels[channel][frame] = 0 }
        }
        channels[0][253] = 0.8
        channels[1][24_013] = -0.4
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let loaded = await EditorAudioWaveform.load(.init(asset: AVURLAsset(url: url), duration: 1))
        let waveform = try XCTUnwrap(loaded)
        XCTAssertEqual(waveform.levels[0].count, 1_000)
        XCTAssertEqual(waveform.amplitude(.init(index: 5, count: 1_000)), 1, accuracy: 0.0001)
        XCTAssertEqual(waveform.amplitude(.init(index: 500, count: 1_000)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(waveform.amplitude(.init(index: 4, count: 1_000)), 0)
        XCTAssertEqual(waveform.amplitude(.init(index: 501, count: 1_000)), 0)
    }

    func testTimestampGapsStaySilentAndOppositeChannelsDoNotCancel() {
        var accumulator = EditorAudioPeakAccumulator(duration: 2)
        let samples: [Float] = [0.7, -0.7, 0, 0, 0, 0, 0.4, -0.4]
        samples.withUnsafeBufferPointer {
            accumulator.append(.init(samples: $0, startTime: 1.25, sampleRate: 1_000, channelCount: 2))
        }
        XCTAssertTrue(accumulator.peaks[..<1_250].allSatisfy { $0 == 0 })
        XCTAssertEqual(accumulator.peaks[1_250], 0.7)
        XCTAssertEqual(accumulator.peaks[1_251], 0)
        XCTAssertEqual(accumulator.peaks[1_253], 0.4)
        XCTAssertTrue(accumulator.peaks[1_254...].allSatisfy { $0 == 0 })
    }

    func testLongRecordingRetainsMillisecondResolution() {
        var accumulator = EditorAudioPeakAccumulator(duration: 1_978)
        let samples: [Float] = [1, 0, 0.5]
        samples.withUnsafeBufferPointer {
            accumulator.append(.init(samples: $0, startTime: 1_700.001, sampleRate: 1_000, channelCount: 1))
        }
        XCTAssertEqual(accumulator.peaks.count, 1_978_000)
        XCTAssertEqual(accumulator.peaks[1_700_001], 1)
        XCTAssertEqual(accumulator.peaks[1_700_002], 0)
        XCTAssertEqual(accumulator.peaks[1_700_003], 0.5)
    }

    func testPeakPyramidMatchesExactRangesAtEveryZoom() {
        let values = (0..<4_097).map { Float(($0 * 37) % 101) / 100 }
        let waveform = EditorAudioWaveform(.init(peaks: values))
        for count in [1, 3, 127, 1_024, 8_192] {
            for index in 0..<count {
                let start = index * values.count / count
                let end = max(start + 1, (index + 1) * values.count / count)
                XCTAssertEqual(waveform.amplitude(.init(index: index, count: count)), values[start..<end].max())
            }
        }
        XCTAssertLessThanOrEqual(waveform.overview.count, 4_096)
        XCTAssertLessThan(waveform.levels.reduce(0) { $0 + $1.count }, values.count * 2 + 20)
    }
}
