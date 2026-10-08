import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class CaptureWriterRecoveryTests: XCTestCase {
    func testSourceWriterCannotReplaceExistingRecording() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 10))
        let original = try Data(contentsOf: fixture.take.screenURL)
        XCTAssertThrowsError(try VideoFileWriter(
            url: fixture.take.screenURL, width: 640, height: 360,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        ))
        XCTAssertEqual(try Data(contentsOf: fixture.take.screenURL), original)
    }

    func testScreenCaptureHasReadableCheckpointBeforeFinalization() async throws {
        let fixture = try SyntheticRecording()
        let writer = try VideoFileWriter(
            url: fixture.take.screenURL, width: 640, height: 360,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        )
        for frame in 0..<360 {
            writer.append(try fixture.videoSample(at: frame))
            try await Task.sleep(for: .milliseconds(3))
        }
        try await Task.sleep(for: .milliseconds(100))
        let checkpoint = fixture.root.appendingPathComponent("checkpoint.mov")
        try FileManager.default.copyItem(at: fixture.take.screenURL, to: checkpoint)
        _ = try await writer.finish()
        try await verifyReadableCheckpoint(checkpoint)
    }

    func testDirectCaptureHasReadableCheckpointBeforeFinalization() async throws {
        let fixture = try SyntheticRecording()
        let writer = try DirectMovieWriter(take: fixture.take, settings: fixture.settings)
        let start = CMClockGetTime(CMClockGetHostTimeClock())
        for frame in 0..<360 {
            let time = CMTimeAdd(start, CMTime(value: Int64(frame), timescale: 30))
            writer.appendVideo(sourceTime: time) { buffer in
                SyntheticRecording.fill(buffer)
                return true
            }
            try await Task.sleep(for: .milliseconds(3))
        }
        try await Task.sleep(for: .milliseconds(100))
        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.take.scratchDirectory, includingPropertiesForKeys: nil
        )
        let partial = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("interrupted-recording-") })
        let checkpoint = fixture.root.appendingPathComponent("checkpoint.mov")
        try FileManager.default.copyItem(at: partial, to: checkpoint)
        _ = try await writer.finish()
        try await verifyReadableCheckpoint(checkpoint)
    }

    func testDirectCaptureRejectsRepeatedAndLateFrameTimes() async throws {
        let fixture = try SyntheticRecording()
        let writer = try DirectMovieWriter(take: fixture.take, settings: fixture.settings)
        let start = CMClockGetTime(CMClockGetHostTimeClock())
        for frame in [0, 1, 2, 2, 1, 3, 4, 5] {
            let time = CMTimeAdd(start, CMTime(value: Int64(frame), timescale: 30))
            writer.appendVideo(sourceTime: time) { buffer in
                SyntheticRecording.fill(buffer)
                return true
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        let completion = try await writer.finish()
        XCTAssertTrue(completion.wroteMedia)
        let duration = try await AVURLAsset(url: XCTUnwrap(completion.url)).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.1)
    }

    private func verifyReadableCheckpoint(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 1)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        while output.copyNextSampleBuffer() != nil { count += 1 }
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(reader.status, .completed)
    }
}
