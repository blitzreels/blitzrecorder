import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class CallSpeechRecoveryTests: XCTestCase {
    private struct FixtureRequest {
        let microphoneLevel: Float
        let intervals: [DiarizedInterval]
    }

    private func recover(_ request: FixtureRequest) throws -> CallSpeechRecovery.Result {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        var tracks: [PreparedTranscriptionTrack] = []
        for source in [RecordingTranscriptAssembler.WordSource.microphone, .systemAudio] {
            let url = root.appendingPathComponent(source == .microphone ? "mic.caf" : "call.caf")
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 192_000))
            buffer.frameLength = 192_000
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            channel.initialize(repeating: source == .microphone ? request.microphoneLevel : 0.1, count: 192_000)
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            tracks.append(.init(source: source, audioURL: url, duration: 12))
        }
        return try CallSpeechRecovery.recover(.init(
            tracks: tracks,
            words: [.init(text: "Where?", startTime: 10, endTime: 10.5, confidence: 0.9)],
            sources: [.microphone], intervals: request.intervals
        ))
    }

    func testQuietRemoteSpeechMissedByDiarizerUsesCallTrack() throws {
        let result = try recover(.init(microphoneLevel: 0.001, intervals: [
            .init(speakerID: "mic-host", startTime: 0, endTime: 4),
            .init(speakerID: "sys-guest", startTime: 5, endTime: 7)
        ]))
        XCTAssertEqual(result.sources, [.systemAudio])
        XCTAssertEqual(result.intervals.last?.speakerID, "sys-guest")
        XCTAssertEqual(result.intervals.last?.startTime, 10)
        XCTAssertEqual(result.intervals.last?.embedding, [])
    }

    func testLoudMicrophoneSpeechKeepsItsSource() throws {
        let result = try recover(.init(microphoneLevel: 0.15, intervals: [
            .init(speakerID: "mic-host", startTime: 0, endTime: 4),
            .init(speakerID: "sys-guest", startTime: 5, endTime: 7)
        ]))
        XCTAssertEqual(result.sources, [.microphone])
        XCTAssertEqual(result.intervals.count, 2)
    }

    func testDetectedMicrophoneVoiceWinsDuringOverlap() throws {
        let result = try recover(.init(microphoneLevel: 0.001, intervals: [
            .init(speakerID: "mic-host", startTime: 10, endTime: 11),
            .init(speakerID: "sys-guest", startTime: 5, endTime: 7)
        ]))
        XCTAssertEqual(result.sources, [.microphone])
    }

    func testMultipleRemoteVoicesDoNotGuessAnIdentityInTheGap() throws {
        let result = try recover(.init(microphoneLevel: 0.001, intervals: [
            .init(speakerID: "mic-host", startTime: 0, endTime: 4),
            .init(speakerID: "sys-guest", startTime: 5, endTime: 7),
            .init(speakerID: "sys-other", startTime: 11, endTime: 12)
        ]))
        XCTAssertEqual(result.sources, [.microphone])
        XCTAssertEqual(result.intervals.count, 3)
    }
}
