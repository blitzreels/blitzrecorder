import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class EditorAudioChunkTests: XCTestCase {
    func testTenSecondsOfSoundInTwentyMinutesProducesOneChunk() {
        let windows = (0..<12_000).map { index in
            SilenceWindow(start: Double(index) / 10, end: Double(index + 1) / 10,
                decibels: (3_000..<3_100).contains(index) ? -18 : -96)
        }
        let ranges = EditorAudioActivity.ranges(.init(windows: windows, duration: 1200))
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].start, 299.97, accuracy: 0.001)
        XCTAssertEqual(ranges[0].end, 310.03, accuracy: 0.001)
        XCTAssertEqual(EditorAudioActivity.ranges(.init(windows: [], duration: 1200)), [])
    }

    func testSeparateSoundsRemainSeparateAndProjectThroughCutsWithSourceOffset() {
        let ranges = EditorAudioActivity.ranges(.init(windows: [
            .init(start: 1, end: 2, decibels: -20), .init(start: 2.2, end: 3, decibels: -20),
            .init(start: 8, end: 9, decibels: -20)
        ], duration: 10))
        XCTAssertEqual(ranges.count, 2)
        let chunks = EditorAudioChunk.resolve(.init(ranges: ranges, sourceOffset: 1, duration: 12,
            projection: .init(.init(duration: 12, cuts: [.init(start: 5, end: 7, kind: .manual, source: .user)]))))
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].region.start, 1.97, accuracy: 0.002)
        XCTAssertEqual(chunks[1].start, 6.97, accuracy: 0.002)
        XCTAssertEqual(chunks[1].region.start, 8.97, accuracy: 0.002)
    }

    func testChunkVolumeSurvivesCodingAndAutomationFollowsCutAndPlaybackRate() throws {
        var levels = try JSONDecoder().decode(EditorAudioLevels.self, from: Data(#"{"microphone":0.8,"systemAudio":0.5}"#.utf8))
        let first = EditorAudioVolumeRegion(source: .systemAudio, start: 4, end: 8, volume: 0.25)
        let second = EditorAudioVolumeRegion(source: .systemAudio, start: 10, end: 11, volume: 0.5)
        levels.setRegion(first)
        levels.setRegion(second)
        XCTAssertEqual(try JSONDecoder().decode(EditorAudioLevels.self, from: JSONEncoder().encode(levels)), levels)
        let parameters = AVMutableAudioMixInputParameters()
        EditorAudioVolumeAutomation.apply(.init(parameters: parameters, source: .systemAudio, baseVolume: 0.5,
            regions: levels.regions, timeMap: .init(takeDuration: .init(seconds: 12),
                cuts: [.init(start: 5, end: 7, kind: .manual, source: .user)], playbackRate: 2)))
        var start: Float = -1
        var end: Float = -1
        var range = CMTimeRange.zero
        XCTAssertTrue(parameters.getVolumeRamp(for: .init(seconds: 2.25, preferredTimescale: 600),
            startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0.125, accuracy: 0.001)
        XCTAssertEqual(end, start, accuracy: 0.001)
        XCTAssertTrue(parameters.getVolumeRamp(for: .init(seconds: 3.5, preferredTimescale: 600),
            startVolume: &start, endVolume: &end, timeRange: &range))
        XCTAssertEqual(start, 0.5, accuracy: 0.001)
        levels.setRegion(.init(source: .systemAudio, start: 4, end: 8, volume: 1))
        XCTAssertEqual(levels.regionVolume(first), 1)
        XCTAssertEqual(levels.regionVolume(second), 0.5)
    }

    func testExportLowersOnlyTheChosenSystemAudioChunk() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 144_000))
        buffer.frameLength = 144_000
        for index in 0..<144_000 {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 880 / 48_000) * 0.2)
        }
        do {
            let file = try AVAudioFile(forWriting: fixture.take.systemAudioURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000])
            try file.write(from: buffer)
        }
        var settings = fixture.settings
        settings.enabledSources = [.screen, .systemAudio]
        settings.audioVolumeRegions = [.init(source: .systemAudio, start: 0, end: 1, volume: 0.25)]
        let output = try await Merger.exportFinalVideo(.init(take: fixture.take, settings: settings, sceneEvents: [],
            backgroundMusic: nil, destinationURL: fixture.root.appendingPathComponent("chunks.mov"), progressHandler: nil))
        let windows = try await SilenceDetection.windows(.init(audioURL: output, takeDuration: 3, sourceOffset: 0,
            minimumSilence: 0.1, thresholdDB: -42, previousCuts: []))
        let quiet = windows.filter { $0.start > 0.15 && $0.end < 0.85 }.map(\.decibels)
        let full = windows.filter { $0.start > 2.15 && $0.end < 2.85 }.map(\.decibels)
        XCTAssertFalse(quiet.isEmpty)
        XCTAssertFalse(full.isEmpty)
        let delta = quiet.reduce(0, +) / Double(quiet.count) - full.reduce(0, +) / Double(full.count)
        XCTAssertEqual(delta, 20 * log10(0.25), accuracy: 0.4)
        print("AUDIO_CHUNK_EXPORT chosen_vs_unchanged_db=\(delta)")
    }
}
