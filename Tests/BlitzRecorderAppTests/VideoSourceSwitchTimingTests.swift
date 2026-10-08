import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class VideoSourceSwitchTimingTests: XCTestCase {
    func testSourceSwitchWithRepeatedTimestampKeepsVideoReadable() async throws {
        try await verifySwitch(.init(
            times: [0, 1, 2, 2, 3, 4, 5].map { CMTime(value: $0, timescale: 30) },
            expectedFrames: 6
        ))
    }

    func testSourceSwitchWithLateFrameKeepsVideoReadable() async throws {
        try await verifySwitch(.init(
            times: [0, 1, 2, 1, 3, 4, 5].map { CMTime(value: $0, timescale: 30) },
            expectedFrames: 6
        ))
    }

    func testSourceSwitchPreservesDistinctHighPrecisionTimestamps() async throws {
        try await verifySwitch(.init(
            times: [0, 33_333, 66_667, 66_668, 100_000, 133_333, 166_667].map {
                CMTime(value: $0, timescale: 1_000_000)
            },
            expectedFrames: 7
        ))
    }

    private struct SwitchScenario {
        let times: [CMTime]
        let expectedFrames: Int
    }

    private func verifySwitch(_ scenario: SwitchScenario) async throws {
        let fixture = try SyntheticRecording()
        let writer = try VideoFileWriter(
            url: fixture.take.screenURL, width: 640, height: 360,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        )
        for time in scenario.times {
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: time,
                decodeTimeStamp: .invalid
            )
            var sample: CMSampleBuffer?
            let status = CMSampleBufferCreateCopyWithNewTiming(
                allocator: nil, sampleBuffer: try fixture.videoSample(at: 0),
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &sample
            )
            XCTAssertEqual(status, noErr)
            writer.append(try XCTUnwrap(sample))
            try await Task.sleep(for: .milliseconds(40))
        }
        let completion = try await writer.finish()
        XCTAssertTrue(completion.wroteMedia)
        let asset = AVURLAsset(url: fixture.take.screenURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(times.count, scenario.expectedFrames)
        for pair in zip(times, times.dropFirst()) {
            XCTAssertGreaterThan(pair.1, pair.0)
        }
        XCTAssertEqual(try XCTUnwrap(times.last), 5.0 / 30.0, accuracy: 0.001)
    }
}
