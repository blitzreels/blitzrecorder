import AVFoundation
import FluidAudio
import Foundation
import XCTest
@testable import BlitzRecorderApp

struct AssemblyCapture: Codable {
    struct Word: Codable { let word: TranscriptWord; let source: String }
    struct Interval: Codable { let speakerID: String; let startTime: Double; let endTime: Double; let embedding: [Float] }
    let duration: Double
    var words: [Word]
    var intervals: [Interval]

    var request: RecordingTranscriptAssembler.Request {
        .init(mediaPath: "", generatedAt: Date(), duration: duration, confidence: 1, text: "", suggestedTitle: nil,
              words: words.map(\.word),
              wordSources: words.map { $0.source == "microphone" ? .microphone : $0.source == "systemAudio" ? .systemAudio : .mixed },
              diarizedIntervals: intervals.map {
                  DiarizedInterval(speakerID: $0.speakerID, startTime: $0.startTime, endTime: $0.endTime, embedding: $0.embedding)
              })
    }
}

final class LocalTranscriptionQualityTests: XCTestCase {
    func testMicrophoneDiarizationDoesNotForceOneSpeaker() {
        let speakers = LocalTranscriptionEngine.microphoneDiarizerConfiguration(.automatic).clustering
        XCTAssertNil(speakers.numSpeakers)
        XCTAssertEqual(speakers.minSpeakers, 1)
        XCTAssertGreaterThanOrEqual(speakers.maxSpeakers ?? 0, 2)
        XCTAssertEqual(
            LocalTranscriptionEngine.microphoneDiarizerConfiguration(.two).clustering.numSpeakers,
            2
        )
    }

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
            let transcript = try await engine.transcribe(.init(
                source: .recording(url),
                model: .parakeet,
                language: .automatic,
                speakerCount: .automatic,
                onUpdate: { _ in }
            ))
            XCTAssertTrue(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(transcript.words?.isEmpty == true)
            XCTAssertEqual(transcript.duration, 10, accuracy: 0.01)
        }
    }

    /// Dumps per-track words and speaker intervals so speaker assembly can be replayed without the models.
    func testAssemblyInputCaptureWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let projectPath = environment["BLITZRECORDER_ASSEMBLY_CAPTURE_PROJECT"],
              let outputPath = environment["BLITZRECORDER_ASSEMBLY_CAPTURE_OUTPUT"] else {
            throw XCTSkip("Set a project and an output file to capture transcript assembly input.")
        }
        let store = LocalTranscriptionModelStore()
        guard store.isInstalled(.parakeet) else { throw XCTSkip("Local transcription models are not installed.") }
        let prepared = try await TranscriptionAudioPreparer().prepare(.project(URL(fileURLWithPath: projectPath)))
        defer { for track in prepared.tracks { try? FileManager.default.removeItem(at: track.audioURL) } }
        let asr = AsrManager(config: LocalTranscriptionEngine.recognitionConfiguration,
                             models: try await AsrModels.load(from: store.asrDirectory, version: .v3))
        let diarizerModels = try await OfflineDiarizerModels.load(from: store.diarizationDirectory)
        var capture = AssemblyCapture(duration: prepared.duration, words: [], intervals: [])
        for track in prepared.tracks {
            var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
            let result = try await asr.transcribe(track.audioURL, decoderState: &state)
            let source = track.source == .microphone ? "microphone" : track.source == .systemAudio ? "systemAudio" : "mixed"
            capture.words += LocalTranscriptionEngine.words(result.tokenTimings ?? []).map { .init(word: $0, source: source) }
            let diarizer = OfflineDiarizerManager(config: track.source == .microphone
                ? LocalTranscriptionEngine.microphoneDiarizerConfiguration(.automatic)
                : LocalTranscriptionEngine.systemDiarizerConfiguration)
            diarizer.initialize(models: diarizerModels)
            let prefix = track.source == .microphone ? RecordingTranscriptAssembler.microphoneSpeakerPrefix
                : RecordingTranscriptAssembler.systemSpeakerPrefix
            if let segments = try? await diarizer.process(track.audioURL).segments {
                capture.intervals += LocalTranscriptionEngine.intervals(segments, prefix: prefix).map {
                    .init(speakerID: $0.speakerID, startTime: $0.startTime, endTime: $0.endTime, embedding: $0.embedding)
                }
            }
        }
        try JSONEncoder().encode(capture).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    func testAssemblyReplayWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_ASSEMBLY_REPLAY"] else {
            throw XCTSkip("Set a captured assembly input to replay speaker assignment.")
        }
        let capture = try JSONDecoder().decode(AssemblyCapture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let request = capture.request
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(request.diarizedIntervals)
        print("labels", labels.sorted { $0.key < $1.key })
        let transcript = RecordingTranscriptAssembler.assemble(request)
        let counts = Dictionary(grouping: transcript.words ?? [], by: { $0.speakerID ?? "-" }).mapValues(\.count)
        print("speakers", transcript.speakers.map { "\($0.id)=\($0.name)" }, counts.sorted { $0.key < $1.key })
        try Data((transcript.segments.map { "\(Int($0.startTime))\t\($0.speakerID)\t\($0.text)" }.joined(separator: "\n")).utf8)
            .write(to: URL(fileURLWithPath: path + ".txt"))
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
