import AVFoundation
import FluidAudio
import Foundation
import XCTest
@testable import BlitzRecorderApp

final class LocalTranscriptionQualityTests: XCTestCase {
    func testSilenceAndNonSpeechDoNotProduceInventedWordsWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_TRANSCRIPTION_EVALUATION_OUTPUT"] != nil else {
            throw XCTSkip("Enable the local transcription evaluation to run installed-model noise checks.")
        }
        guard LocalTranscriptionModelStore().isInstalled else { throw XCTSkip("Local models are not installed.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let engine = LocalTranscriptionEngine()
        for hasImpacts in [false, true] {
            let url = root.appendingPathComponent(hasImpacts ? "impacts.caf" : "silence.caf")
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000))
            buffer.frameLength = 160_000
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<160_000 {
                let position = index % 40_000
                samples[index] = hasImpacts && position < 3_200
                    ? Float(sin(Double(position) * 1.7) * exp(-Double(position) / 400)) * 0.7 : 0
            }
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            let transcript = try await engine.transcribe(.init(source: .recording(url), onUpdate: { _ in }))
            XCTAssertTrue(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(transcript.words?.isEmpty == true)
            XCTAssertEqual(transcript.duration, 10, accuracy: 0.01)
        }
    }

    func testLocalModelComparisonWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let projectPath = environment["BLITZRECORDER_TRANSCRIPTION_EVALUATION_PROJECT"],
              let outputPath = environment["BLITZRECORDER_TRANSCRIPTION_EVALUATION_OUTPUT"] else {
            throw XCTSkip("Set a local evaluation project and output directory to compare installed models.")
        }
        let store = LocalTranscriptionModelStore()
        guard store.isInstalled else { throw XCTSkip("Local transcription models are not installed.") }
        let prepared = try await TranscriptionAudioPreparer().prepare(.project(URL(fileURLWithPath: projectPath)))
        defer {
            for track in prepared.tracks {
                try? FileManager.default.removeItem(at: track.audioURL)
            }
        }
        let models = try await AsrModels.load(from: store.asrDirectory, version: .v3)
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for quality in [false, true] {
            let manager = AsrManager(config: ASRConfig(
                melChunkContext: false, dualDecodeArbitration: quality
            ), models: models)
            let name = quality ? "quality" : "baseline"
            for (index, track) in prepared.tracks.enumerated() {
                var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
                let result = try await manager.transcribe(track.audioURL, decoderState: &state)
                XCTAssertGreaterThan(prepared.duration, 0)
                XCTAssertTrue((result.tokenTimings ?? []).allSatisfy {
                    $0.startTime.isFinite && $0.endTime.isFinite && $0.startTime >= 0
                        && $0.endTime >= $0.startTime && $0.endTime <= prepared.duration + 0.1
                })
                try encoder.encode(result).write(
                    to: output.appendingPathComponent("\(name)-\(index).json"),
                    options: .atomic
                )
            }
        }
    }
}
