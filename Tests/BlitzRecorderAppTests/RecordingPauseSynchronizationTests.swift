import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class RecordingPauseSynchronizationTests: XCTestCase {
    func testAudioAndStaticVideoExcludeTheSamePause() async throws {
        try await verifyPauses(.init(count: 1, suppliesPausedVideo: false, audioFormat: .aac))
    }

    func testRepeatedPausesWithVideoFramesKeepAACInSync() async throws {
        try await verifyPauses(.init(count: 3, suppliesPausedVideo: true, audioFormat: .aac))
    }

    func testRepeatedStaticScreenPausesKeepLosslessAudioInSync() async throws {
        try await verifyPauses(.init(count: 2, suppliesPausedVideo: false, audioFormat: .wav))
    }

    private struct PauseScenario {
        let count: Int
        let suppliesPausedVideo: Bool
        let audioFormat: SourceAudioFormat
    }

    private func verifyPauses(_ scenario: PauseScenario) async throws {
        let fixture = try SyntheticRecording()
        let video = try VideoFileWriter(
            url: fixture.take.screenURL, width: 640, height: 360,
            bitrate: 1_000_000, fps: 30, outputFormat: .mov
        )
        let audioURL = fixture.root.appendingPathComponent("audio.\(scenario.audioFormat.fileExtension)")
        let audio = try AudioSampleFileWriter(url: audioURL, format: scenario.audioFormat)
        let start = CMClockGetTime(CMClockGetHostTimeClock())
        var pauseDuration = CMTime.zero
        for segment in 0...scenario.count {
            for frame in (segment * 6)..<((segment + 1) * 6) {
                let time = CMTimeAdd(
                    CMTimeAdd(start, CMTime(value: Int64(frame), timescale: 30)), pauseDuration
                )
                video.append(try retime(.init(sample: fixture.videoSample(at: frame), time: time)))
                audio.append(try retime(.init(sample: fixture.audioSample(at: frame), time: time)))
                try await Task.sleep(for: .milliseconds(10))
            }
            guard segment < scenario.count else { continue }
            let pauseStart = CMClockGetTime(CMClockGetHostTimeClock())
            video.pause()
            audio.pause()
            try await Task.sleep(for: .milliseconds(100))
            video.pause()
            audio.pause()
            let pausedTime = CMTimeAdd(
                CMTimeAdd(start, pauseDuration),
                CMTime(seconds: Double(segment + 1) * 0.2 + 0.1, preferredTimescale: 48_000)
            )
            if scenario.suppliesPausedVideo {
                video.append(try retime(.init(sample: fixture.videoSample(at: 0), time: pausedTime)))
            }
            audio.append(try retime(.init(sample: fixture.audioSample(at: 0), time: pausedTime)))
            try await Task.sleep(for: .milliseconds(300))
            pauseDuration = CMTimeAdd(
                pauseDuration, CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), pauseStart)
            )
            video.resume()
            audio.resume()
            video.resume()
            audio.resume()
        }
        let videoCompletion = try await video.finish()
        let audioCompletion = try await audio.finish()
        XCTAssertTrue(videoCompletion.wroteMedia)
        XCTAssertTrue(audioCompletion.wroteMedia)
        let videoTimes = try await presentationTimes(.init(url: fixture.take.screenURL, mediaType: .video))
        let videoDuration = try await AVURLAsset(url: fixture.take.screenURL).load(.duration).seconds
        let audioDuration = try await AVURLAsset(url: audioURL).load(.duration).seconds
        let expectedDuration = Double(scenario.count + 1) * 0.2
        XCTAssertEqual(try XCTUnwrap(videoTimes.last), expectedDuration, accuracy: 0.04)
        XCTAssertEqual(videoDuration, audioDuration, accuracy: 0.04)
        XCTAssertEqual(audioDuration, expectedDuration, accuracy: 0.04)
        for pair in zip(videoTimes, videoTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1, pair.0)
            XCTAssertLessThanOrEqual(pair.1 - pair.0, 0.04)
        }
    }

    private struct RetimeRequest {
        let sample: CMSampleBuffer
        let time: CMTime
    }

    private func retime(_ request: RetimeRequest) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo()
        XCTAssertEqual(CMSampleBufferGetSampleTimingInfo(request.sample, at: 0, timingInfoOut: &timing), noErr)
        timing.presentationTimeStamp = request.time
        var result: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: request.sample, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleBufferOut: &result
        )
        XCTAssertEqual(status, noErr)
        return try XCTUnwrap(result)
    }

    private struct InspectionRequest {
        let url: URL
        let mediaType: AVMediaType
    }

    private func presentationTimes(_ request: InspectionRequest) async throws -> [Double] {
        let asset = AVURLAsset(url: request.url)
        let tracks = try await asset.loadTracks(withMediaType: request.mediaType)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            if time.isNumeric { times.append(time.seconds) }
        }
        XCTAssertEqual(reader.status, .completed)
        return times
    }
}
