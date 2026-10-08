import XCTest
import WhisperKit
@testable import BlitzRecorderApp

final class SpeakerIdentityTests: XCTestCase {
    private func voice(_ values: [Float]) -> SpeakerVoice {
        .init(embedding: values + Array(repeating: 0, count: 256 - values.count), duration: 12)
    }

    private func transcript(_ text: String) -> RecordingTranscript {
        .init(version: 2, id: UUID(), mediaPath: "/recording.mov", generatedAt: Date(), duration: 12,
              confidence: 0.9, text: text, suggestedTitle: nil,
              speakers: [.init(id: "Speaker 1", name: "", context: "", voice: voice([1, 0]))],
              segments: [.init(id: UUID(), speakerID: "Speaker 1", startTime: 0, endTime: 12,
                               text: text, confidence: 0.9)])
    }

    func testOldSpeakerJSONRemainsReadable() throws {
        let speaker = try JSONDecoder().decode(RecordingTranscript.Speaker.self,
            from: Data(#"{"id":"Speaker 1","name":"Alice","context":"Host"}"#.utf8))
        XCTAssertNil(speaker.voice)
        XCTAssertNil(speaker.identitySuggestion)
        XCTAssertEqual(speaker.displayName, "Alice")
    }

    func testConfirmedNameIsNeverReplacedBySuggestion() {
        let original = transcript("My name is Alice.").renamingSpeaker(.init(speakerID: "Speaker 1", name: "Bob"))
        XCTAssertNil(SpeakerIdentity.suggestingNames(.init(transcript: original, profiles: [])).speakers[0].identitySuggestion)
    }

    func testIntroductionIncludesEvidenceWithoutInventedProbability() throws {
        for text in ["My name is Alice.", "Bonjour, je m’appelle Alice.", "Hello! My name is Alice."] {
            let result = SpeakerIdentity.suggestingNames(.init(transcript: transcript(text), profiles: []))
            let suggestion = try XCTUnwrap(result.speakers[0].identitySuggestion)
            XCTAssertEqual(suggestion.name, "Alice")
            XCTAssertEqual(suggestion.evidence, text)
            XCTAssertNil(suggestion.voiceSimilarity)
            XCTAssertEqual(result.speakers[0].name, "")
        }
    }

    func testMentioningSomeoneElseDoesNotNameTheSpeaker() {
        for text in ["Alice, can you share your screen?", "She said my name is Alice.", "I am Building a website.",
                     "My name is Alice. My name is Bob."] {
            let result = SpeakerIdentity.suggestingNames(.init(transcript: transcript(text), profiles: []))
            XCTAssertNil(result.speakers[0].identitySuggestion, text)
        }
    }

    func testAmbiguousVoiceDoesNotPickBetweenTwoPeople() {
        let profiles = [
            SavedSpeakerVoice(id: UUID(), name: "Alice", samples: [voice([1, 0])]),
            SavedSpeakerVoice(id: UUID(), name: "Bob", samples: [voice([0.99, 0.1])])
        ]
        XCTAssertNil(SpeakerIdentity.match(.init(voice: voice([1, 0]), profiles: profiles)))
    }

    func testSameTwoPeopleAreRecognizedWhenTheirOrderChangesAcrossThreeVideos() throws {
        let alice = SavedSpeakerVoice(id: UUID(), name: "Alice", samples: [voice([1, 0])])
        let bob = SavedSpeakerVoice(id: UUID(), name: "Bob", samples: [voice([0, 1])])
        for index in 0..<3 {
            var recording = transcript("A conversation about software.")
            let samples = index.isMultiple(of: 2) ? [voice([1, 0.05]), voice([0.02, 1])]
                : [voice([0.02, 1]), voice([1, 0.05])]
            recording.speakers = samples.enumerated().map {
                .init(id: "Speaker \($0.offset + 1)", name: "", context: "", voice: $0.element)
            }
            let result = SpeakerIdentity.suggestingNames(.init(transcript: recording, profiles: [alice, bob]))
            XCTAssertEqual(result.speakers.compactMap { $0.identitySuggestion?.name },
                           index.isMultiple(of: 2) ? ["Alice", "Bob"] : ["Bob", "Alice"])
            XCTAssertTrue(result.speakers.allSatisfy { $0.name.isEmpty })
        }
    }

    func testOneProfileCannotBeSuggestedForTwoSpeakersInOneRecording() {
        var recording = transcript("A conversation about software.")
        recording.speakers.append(.init(id: "Speaker 2", name: "", context: "", voice: voice([1, 0])))
        let profile = SavedSpeakerVoice(id: UUID(), name: "Alice", samples: [voice([1, 0])])
        let result = SpeakerIdentity.suggestingNames(.init(transcript: recording, profiles: [profile]))
        XCTAssertTrue(result.speakers.allSatisfy { $0.identitySuggestion == nil })
    }

    func testShortInvalidOrDifferentModelSamplesDoNotMatch() {
        let profile = SavedSpeakerVoice(id: UUID(), name: "Alice", samples: [voice([1, 0])])
        var differentModel = voice([1, 0])
        differentModel.model = "future-model"
        for sample in [SpeakerVoice(embedding: voice([1, 0]).embedding, duration: 1),
                       SpeakerVoice(embedding: [1, 0], duration: 10), voice([.nan, 0]),
                       voice([0, 0]), differentModel] {
            XCTAssertNil(SpeakerIdentity.match(.init(voice: sample, profiles: [profile])))
        }
    }

    func testSavedVoiceSurvivesReopeningAndCanBeForgotten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("voices.json")
        let store = SpeakerVoiceStore(url: url)
        let id = try await store.remember(.init(name: "Alice", voice: voice([1, 0]), profileID: nil))
        let reopened = SpeakerVoiceStore(url: url)
        let saved = try await reopened.profiles()
        XCTAssertEqual(saved.map(\.name), ["Alice"])
        let updatedID = try await reopened.remember(.init(name: "Alice Smith", voice: voice([1, 0]), profileID: id))
        XCTAssertEqual(updatedID, id)
        let updated = try await store.profiles()
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].samples.count, 1)
        XCTAssertEqual(updated[0].name, "Alice Smith")
        try await reopened.forget(id)
        let remaining = try await store.profiles()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCorruptVoiceStoreIsNotOverwritten() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not valid JSON".utf8)
        try data.write(to: url)
        do {
            _ = try await SpeakerVoiceStore(url: url).remember(.init(name: "Alice", voice: voice([1, 0]), profileID: nil))
            XCTFail("Expected a corrupt-store error")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testVocabularyDeduplicatesAndBoundsHints() {
        XCTAssertEqual(TranscriptionVocabulary.terms(.init(custom: "BlitzReels, API\nBlitzReels", names: ["Alice", "alice"])),
                       ["BlitzReels", "API", "Alice"])
        XCTAssertEqual(TranscriptionVocabulary.terms(.init(custom: "", names: (0..<100).map { "Name\($0)" })).count, 40)
    }

    func testQuietGuestWithDistinctVoiceIsKeptAndFingerprintsPersist() throws {
        let words = (0..<102).map { index in
            TranscriptWord(text: index < 100 ? "host" : "guest", startTime: Double(index),
                           endTime: Double(index) + 0.8, confidence: 0.9)
        }
        let result = RecordingTranscriptAssembler.assemble(.init(
            mediaPath: "/recording.mov", generatedAt: Date(), duration: 102, confidence: 0.9,
            text: "", suggestedTitle: nil, words: words,
            diarizedIntervals: [
                .init(speakerID: "sys-host", startTime: 0, endTime: 100, embedding: voice([1, 0]).embedding),
                .init(speakerID: "sys-guest", startTime: 100, endTime: 102, embedding: voice([0.6, 0.8]).embedding)
            ]
        ))
        XCTAssertEqual(result.speakers.count, 2)
        XCTAssertEqual(result.speakers[0].voice?.embedding.count, 256)
        XCTAssertEqual(result.words?.suffix(2).compactMap(\.speakerID), ["Speaker 2", "Speaker 2"])
        let roundTrip = try JSONDecoder().decode(RecordingTranscript.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(roundTrip, result)
        XCTAssertFalse(roundTrip.speakers[1].voice?.isUsable ?? true)
    }

    func testRetranscriptionRetainsConfirmedNamesAndProfileLinks() {
        var previous = transcript("My name is Alice.")
        previous.speakers[0].name = "Alice"
        previous.speakers[0].savedVoiceID = UUID()
        let current = transcript("My name is Alice. We are discussing software.")
        let retained = SpeakerIdentity.preservingNames(.init(transcript: current, previous: previous))
        XCTAssertEqual(retained.speakers[0].name, "Alice")
        XCTAssertEqual(retained.speakers[0].savedVoiceID, previous.speakers[0].savedVoiceID)
        XCTAssertEqual(retained.text, current.text)
    }

    func testSimilarShortVoiceOnAnotherTrackNeedsEchoTimingBeforeMerging() {
        let labels = RecordingTranscriptAssembler.voiceClusterLabels([
            .init(speakerID: "sys-0", startTime: 0, endTime: 100, embedding: voice([1, 0]).embedding),
            .init(speakerID: "mic-1", startTime: 101, endTime: 105, embedding: voice([0.6, 0.8]).embedding)
        ])
        XCTAssertNotEqual(labels["sys-0"], labels["mic-1"])
    }

    @MainActor
    func testRenameUndoAndRedoUpdateSavedArtifacts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = TranscriptArtifactStore.Locations(jsonURL: root.appendingPathComponent("transcript.json"),
                                                         textURL: root.appendingPathComponent("transcript.txt"))
        let original = transcript("A conversation about software.")
        let renamed = original.renamingSpeaker(.init(speakerID: "Speaker 1", name: "Alice"))
        let store = TranscriptArtifactStore()
        try store.save(.init(transcript: renamed, locations: locations))
        let manager = UndoManager()
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        TranscriptSpeakerUndo.shared.register(.init(locations: locations, before: original.speakers[0],
            after: renamed.speakers[0], manager: manager, isAvailable: { true }, onError: { XCTFail($0.localizedDescription) }))
        manager.endUndoGrouping()
        manager.undo()
        XCTAssertEqual(try store.load(from: locations.jsonURL).speakers[0].name, "")
        XCTAssertTrue(manager.canRedo)
        manager.redo()
        XCTAssertEqual(try store.load(from: locations.jsonURL).speakers[0].name, "Alice")
    }

    func testRealVoiceAcrossAudioExcerptsWhenRequested() async throws {
        guard let directory = ProcessInfo.processInfo.environment["BLITZRECORDER_VOICE_EVALUATION"] else {
            throw XCTSkip("Set a directory containing sample-1.wav through sample-3.wav for local voice evaluation.")
        }
        let root = URL(fileURLWithPath: directory)
        let engine = LocalTranscriptionEngine()
        var profiles: [SavedSpeakerVoice] = []
        for index in 1...3 {
            let recording = try await engine.transcribe(.init(
                source: .recording(root.appendingPathComponent("sample-\(index).wav")),
                model: .parakeet, language: .automatic, speakerCount: .automatic, onUpdate: { _ in }
            ))
            let speaker = try XCTUnwrap(recording.speakers.max {
                recording.speakingDuration(for: $0.id) < recording.speakingDuration(for: $1.id)
            })
            let sample = try XCTUnwrap(speaker.voice)
            XCTAssertTrue(sample.isUsable)
            if profiles.isEmpty {
                profiles = [.init(id: UUID(), name: "Evaluation speaker", samples: [sample])]
            } else {
                let suggestion = SpeakerIdentity.match(.init(voice: sample, profiles: profiles))
                print("Voice excerpt \(index): \(suggestion?.label ?? "no confident match")")
                XCTAssertEqual(suggestion?.name, "Evaluation speaker")
            }
        }
        let negativeURL = root.appendingPathComponent("different-speaker.wav")
        if FileManager.default.fileExists(atPath: negativeURL.path) {
            let different = try await engine.transcribe(.init(
                source: .recording(negativeURL), model: .parakeet, language: .automatic,
                speakerCount: .automatic, onUpdate: { _ in }
            ))
            for speaker in different.speakers {
                guard let sample = speaker.voice, sample.isUsable else { continue }
                let similarity = 1 - RecordingTranscriptAssembler.cosineDistance(
                    sample.embedding, profiles[0].samples[0].embedding)
                print("Different voice similarity: \(similarity)")
                XCTAssertNil(SpeakerIdentity.match(.init(voice: sample, profiles: profiles)))
            }
        }
    }

    func testWhisperVocabularyOnRealAudioWhenRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["BLITZRECORDER_VOCABULARY_EVALUATION"],
              let vocabulary = environment["BLITZRECORDER_VOCABULARY_HINTS"] else {
            throw XCTSkip("Set an evaluation directory and vocabulary hints to compare Whisper decoding.")
        }
        let folder = try XCTUnwrap(LocalTranscriptionModelStore().whisperModelFolder(.whisperMedium))
        let whisper = try await WhisperKit(.init(modelFolder: folder.path, tokenizerFolder: folder,
                                                load: true, download: false))
        let root = URL(fileURLWithPath: directory)
        let tokenizer = try XCTUnwrap(whisper.tokenizer)
        for hinted in [false, true] {
            let result = try await whisper.transcribe(audioPath: root.appendingPathComponent("sample-1.wav").path,
                decodeOptions: DecodingOptions(language: "en", skipSpecialTokens: true, wordTimestamps: true,
                    promptTokens: hinted ? Array(tokenizer.encode(text: vocabulary).suffix(160)) : nil,
                    suppressBlank: true, chunkingStrategy: .vad))
            let text = result.map(\.text).joined(separator: " ")
            print("Whisper \(hinted ? "with hints" : "baseline"): \(text)")
            XCTAssertFalse(text.isEmpty)
            try text.write(to: root.appendingPathComponent(hinted ? "whisper-hinted.txt" : "whisper-baseline.txt"),
                           atomically: true, encoding: .utf8)
        }
    }
}
