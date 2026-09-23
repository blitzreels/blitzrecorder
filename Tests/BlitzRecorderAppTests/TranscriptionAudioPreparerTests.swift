import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class TranscriptionAudioPreparerTests: XCTestCase {
    func testRecognitionAudioPreservesPCMWithoutAnotherLossyEncode() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: source) }
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.1)) * 0.4 }
        try writeAudio(.init(url: source, samples: samples))
        let original = try Data(contentsOf: source)
        let prepared = try await TranscriptionAudioPreparer().prepare(.recording(source))
        defer { cleanup(prepared) }
        let audio = try AVAudioFile(forReading: try XCTUnwrap(prepared.tracks.first).audioURL)
        XCTAssertEqual(audio.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatLinearPCM)
        XCTAssertEqual(audio.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(audio.processingFormat.channelCount, 1)
        XCTAssertEqual(prepared.duration, 1, accuracy: 1.0 / 16_000)
        let output = try readSamples(audio)
        XCTAssertEqual(output.count, samples.count)
        let largestError = samples.enumerated().map { abs($0.element - output[$0.offset]) }.max() ?? 1
        XCTAssertLessThan(largestError, 0.00001)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testProjectAudioKeepsDelayedSourcesAlignedAndPreventsMixClipping() async throws {
        let fixture = try SyntheticRecording()
        let source = fixture.root.appendingPathComponent("microphone.caf")
        try writeAudio(.init(url: source, samples: Array(repeating: 0.8, count: 16_000)))
        let store = TakeFileStore()
        _ = try store.loadRecordingProject(at: fixture.take.projectURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.take.projectURL)) as? [String: Any])
        object["sources"] = [
            ["role": "microphone", "path": source.path, "exists": true],
            ["role": "systemAudio", "path": source.path, "exists": true]
        ]
        object["sourceTimelineOffsetSeconds"] = ["microphone": 0.75, "systemAudio": 1.25]
        object["timelineTrimOffsetSeconds"] = 0.25
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.take.projectURL)
        let before = try Data(contentsOf: fixture.take.projectURL)
        let prepared = try await TranscriptionAudioPreparer().prepare(.project(fixture.take.projectURL))
        defer { cleanup(prepared) }
        XCTAssertEqual(prepared.tracks.count, 2)
        XCTAssertEqual(prepared.duration, 2, accuracy: 0.01)
        let microphone = try XCTUnwrap(prepared.tracks.first { $0.source == .microphone })
        let systemAudio = try XCTUnwrap(prepared.tracks.first { $0.source == .systemAudio })
        let microphoneSamples = try readSamples(AVAudioFile(forReading: microphone.audioURL))
        let systemSamples = try readSamples(AVAudioFile(forReading: systemAudio.audioURL))
        XCTAssertEqual(microphone.duration, 1.5, accuracy: 0.01)
        XCTAssertEqual(systemAudio.duration, 2, accuracy: 0.01)
        XCTAssertEqual(microphoneSamples[4_000], 0, accuracy: 0.00001)
        XCTAssertEqual(microphoneSamples[12_000], 0.8, accuracy: 0.00001)
        XCTAssertEqual(systemSamples[12_000], 0, accuracy: 0.00001)
        XCTAssertEqual(systemSamples[20_000], 0.8, accuracy: 0.00001)
        XCTAssertEqual(try Data(contentsOf: fixture.take.projectURL), before)
    }

    private func cleanup(_ prepared: PreparedTranscriptionAudio) {
        for track in prepared.tracks {
            try? FileManager.default.removeItem(at: track.audioURL)
        }
    }

    private struct AudioRequest {
        let url: URL
        let samples: [Float]
    }

    private func readSamples(_ audio: AVAudioFile) throws -> [Float] {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096))
        var samples: [Float] = []
        while audio.framePosition < audio.length {
            try audio.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        return samples
    }

    private func writeAudio(_ request: AudioRequest) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
            frameCapacity: AVAudioFrameCount(request.samples.count)))
        buffer.frameLength = AVAudioFrameCount(request.samples.count)
        request.samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count)
        }
        let file = try AVAudioFile(forWriting: request.url, settings: format.settings)
        try file.write(from: buffer)
    }
}
