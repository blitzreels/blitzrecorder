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
    func testAutomaticWhisperLanguageEnablesDetection() {
        let options = LocalTranscriptionEngine.whisperDecodingOptions(.init(language: .automatic, promptTokens: nil))
        XCTAssertTrue(options.detectLanguage)
        XCTAssertNil(options.language)
        XCTAssertTrue(options.wordTimestamps)
    }

    func testExplicitWhisperLanguagePreservesLock() {
        for language in [TranscriptionLanguage.french, .english] {
            let options = LocalTranscriptionEngine.whisperDecodingOptions(.init(language: language, promptTokens: [123]))
            XCTAssertFalse(options.detectLanguage)
            XCTAssertEqual(options.language, language.whisperCode)
            XCTAssertEqual(options.promptTokens, [123])
        }
    }

    func testAutomaticLanguagePreservesFrenchCallWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_FRENCH_CALL_SAMPLE"] else {
            throw XCTSkip("Set a local French call excerpt to verify automatic language detection.")
        }
        let engine = LocalTranscriptionEngine()
        if !LocalTranscriptionModelStore().isInstalled(.whisperLarge) {
            guard ProcessInfo.processInfo.environment["BLITZRECORDER_RESTORE_CALL_MODEL"] == "1" else {
                throw XCTSkip("Install Whisper Large to verify automatic language detection.")
            }
            try await engine.downloadModels(.init(model: .whisperLarge, onUpdate: { _ in }))
        }
        let transcript = try await engine.transcribe(.init(
            source: .recording(URL(fileURLWithPath: path)),
            model: .whisperLarge,
            language: .automatic,
            speakerCount: .automatic,
            onUpdate: { _ in }
        ))
        XCTAssertTrue(transcript.text.lowercased().contains("fondateur"), transcript.text)
        XCTAssertFalse(transcript.text.lowercased().contains("founder"), transcript.text)
    }

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

    func testRetranscribeStagedCallWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_STAGED_CALL_PROJECT"] else {
            throw XCTSkip("Set a staged project copy to verify a complete call transcript.")
        }
        let url = URL(fileURLWithPath: path)
        let project = try TakeFileStore().loadRecordingProject(at: url)
        let locations = TranscriptArtifactStore().locations(for: project)
        XCTAssertEqual(locations.jsonURL.deletingLastPathComponent(), url.deletingLastPathComponent())
        guard locations.jsonURL.deletingLastPathComponent() == url.deletingLastPathComponent() else { return }
        let transcript = try await LocalTranscriptionEngine().transcribe(.init(
            source: .project(url), model: .whisperLarge, language: .automatic, speakerCount: .automatic,
            onUpdate: { update in
                print("CALL \(update.stage) \(update.detail ?? "")")
                fflush(stdout)
            }
        ))
        XCTAssertGreaterThan(transcript.words?.count ?? 0, 100)
        XCTAssertTrue(transcript.segments.allSatisfy {
            $0.startTime >= 0 && $0.endTime >= $0.startTime && $0.endTime <= transcript.duration + 0.2
        })
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
            var configuration = track.source == .microphone
                ? LocalTranscriptionEngine.microphoneDiarizerConfiguration(.automatic)
                : LocalTranscriptionEngine.systemDiarizerConfiguration
            if let value = environment["BLITZRECORDER_DIARIZATION_THRESHOLD"].flatMap(Double.init) {
                configuration.clusteringThreshold = value
            }
            let diarizer = OfflineDiarizerManager(config: configuration)
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

    func testAssemblyReplayWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["BLITZRECORDER_ASSEMBLY_REPLAY"] else {
            throw XCTSkip("Set a captured assembly input to replay speaker assignment.")
        }
        var capture = try JSONDecoder().decode(AssemblyCapture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        if let project = ProcessInfo.processInfo.environment["BLITZRECORDER_ASSEMBLY_CAPTURE_PROJECT"] {
            let prepared = try await TranscriptionAudioPreparer().prepare(.project(URL(fileURLWithPath: project)))
            defer { for track in prepared.tracks { try? FileManager.default.removeItem(at: track.audioURL) } }
            let original = capture.request
            let recovered = try CallSpeechRecovery.recover(.init(
                tracks: prepared.tracks, words: original.words,
                sources: original.wordSources, intervals: original.diarizedIntervals
            ))
            capture.words = zip(original.words, recovered.sources).map { word, source in
                .init(word: word, source: source == .microphone ? "microphone" : source == .systemAudio ? "systemAudio" : "mixed")
            }
            capture.intervals = recovered.intervals.map {
                .init(speakerID: $0.speakerID, startTime: $0.startTime, endTime: $0.endTime, embedding: $0.embedding)
            }
        }
        let request = capture.request
        let labels = RecordingTranscriptAssembler.voiceClusterLabels(.init(
            intervals: request.diarizedIntervals, words: Array(zip(request.words, request.wordSources))
        ))
        if let expected = ProcessInfo.processInfo.environment["BLITZRECORDER_ASSEMBLY_EXPECTED_ECHO"] {
            let pair = expected.split(separator: "=").map(String.init)
            XCTAssertEqual(pair.count, 2)
            if pair.count == 2 { XCTAssertEqual(labels[pair[0]], labels[pair[1]]) }
        }
        print("labels", labels.sorted { $0.key < $1.key })
        let transcript = RecordingTranscriptAssembler.assemble(request)
        if ProcessInfo.processInfo.environment["BLITZRECORDER_ASSEMBLY_EXPECT_REMOTE_QUESTION"] == "1" {
            let question = try XCTUnwrap(transcript.words?.first { $0.text == "Where" })
            let remote = try XCTUnwrap(transcript.words?.first { $0.text == "Yeah," })
            XCTAssertEqual(question.speakerID, remote.speakerID)
        }
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
