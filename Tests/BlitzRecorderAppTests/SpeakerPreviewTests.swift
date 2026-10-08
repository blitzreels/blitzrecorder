import AVFoundation
import XCTest
@testable import BlitzRecorderApp

final class SpeakerPreviewTests: XCTestCase {
    private func voice() -> SpeakerVoice {
        .init(embedding: [1] + Array(repeating: 0, count: 255), duration: 12)
    }

    private func transcript(_ segments: [RecordingTranscript.Segment]) -> RecordingTranscript {
        .init(version: 2, id: UUID(), mediaPath: "/recording.mov", generatedAt: Date(), duration: 60,
              confidence: 0.9, text: "Speech", suggestedTitle: nil,
              speakers: [.init(id: "a", name: "Alice", context: "", voice: voice())], segments: segments)
    }

    private struct SegmentRequest {
        let speaker: String
        let start: Double
        let end: Double
        let confidence: Float
    }

    private func segment(_ request: SegmentRequest) -> RecordingTranscript.Segment {
        .init(id: UUID(), speakerID: request.speaker, startTime: request.start, endTime: request.end,
              text: "Speech", confidence: request.confidence)
    }

    func testExistingProfilesDecodeWithoutAudioPreviews() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Alice","samples":[]}
        """
        let saved = try JSONDecoder().decode(SavedSpeakerVoice.self, from: Data(json.utf8))
        XCTAssertNil(saved.preview)
        XCTAssertEqual(saved.name, "Alice")
    }

    func testSelectionRejectsOverlappingShortAndLowConfidenceSpeech() {
        let recording = transcript([
            segment(.init(speaker: "a", start: 0, end: 4, confidence: 0.9)),
            segment(.init(speaker: "b", start: 2, end: 3, confidence: 0.9)),
            segment(.init(speaker: "a", start: 5, end: 7, confidence: 0.9)),
            segment(.init(speaker: "a", start: 8, end: 12, confidence: 0.4)),
            segment(.init(speaker: "a", start: 15, end: 19, confidence: 0.9)),
            segment(.init(speaker: "a", start: 20, end: 40, confidence: 0.9))
        ])
        let ranges = SpeakerSampleBuilder.ranges(.init(transcript: recording, speakerID: "a"))
        XCTAssertEqual(ranges.map(\.start), [20, 15])
        XCTAssertEqual(ranges.map(\.end), [32, 19])
    }

    func testPreviewRenameReplacementAndForgetPreserveIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SpeakerVoiceStore(url: root.appendingPathComponent("voices.json"))
        let id = try await store.remember(.init(name: "Alice", voice: voice(), profileID: nil))
        let input = root.appendingPathComponent("input.m4a")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: input)
        let sample = SpeakerSampleBuilder.Sample(url: input, sourceTitle: "Call", sourceProjectID: UUID(),
                                                duration: 8, text: "Speech")
        try await store.savePreview(.init(profileID: id, sample: sample))
        let firstURL = try await store.sampleURL(for: id)
        let first = try XCTUnwrap(firstURL)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int, 0o600)
        try await store.rename(.init(id: id, name: "  Alice Smith  "))
        let renamed = try await store.profiles()
        XCTAssertEqual(renamed[0].id, id)
        XCTAssertEqual(renamed[0].name, "Alice Smith")
        XCTAssertEqual(renamed[0].samples, [voice()])
        XCTAssertEqual(renamed[0].preview?.sourceProjectID, sample.sourceProjectID)
        try await store.savePreview(.init(profileID: id, sample: sample))
        let secondURL = try await store.sampleURL(for: id)
        let second = try XCTUnwrap(secondURL)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        try await store.forget(id)
        let profiles = try await store.profiles()
        XCTAssertTrue(profiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testInvalidRenameAndFailedPreviewLeaveStoredProfileIntact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("voices.json")
        let store = SpeakerVoiceStore(url: url)
        let id = try await store.remember(.init(name: "Alice", voice: voice(), profileID: nil))
        let before = try Data(contentsOf: url)
        for name in ["  ", "You"] {
            do {
                try await store.rename(.init(id: id, name: name))
                XCTFail("Invalid name accepted")
            } catch { XCTAssertEqual(try Data(contentsOf: url), before) }
        }
        do {
            try await store.savePreview(.init(profileID: id, sample: .init(
                url: root.appendingPathComponent("missing.m4a"), sourceTitle: "Call", sourceProjectID: UUID(),
                duration: 8, text: "Speech"
            )))
            XCTFail("Missing sample accepted")
        } catch { XCTAssertEqual(try Data(contentsOf: url), before) }
    }

    private struct ToneRequest {
        let url: URL
        let silentSeconds: Double
    }

    private func writeTone(_ request: ToneRequest) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: request.url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000))
        buffer.frameLength = 160_000
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<160_000 {
            let time = Double(index) / 16_000
            channel[index] = time < request.silentSeconds ? 0 : Float(sin(time * 440 * 2 * .pi)) * 0.2
        }
        try file.write(from: buffer)
    }

    private struct ProjectRequest {
        let fixture: SyntheticRecording
        let audio: URL
    }

    private func project(_ request: ProjectRequest) throws -> RecordingProject {
        let original = try TakeFileStore().loadRecordingProject(at: request.fixture.take.projectURL)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["sources"] = [["role": "microphone", "path": request.audio.path, "exists": true]]
        json["sourceTimelineOffsetSeconds"] = ["microphone": 1]
        json["timelineTrimOffsetSeconds"] = 3
        return try JSONDecoder().decode(RecordingProject.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testExportUsesSourceOffsetAndTrimAndCreatesPlayableAudio() async throws {
        let fixture = try SyntheticRecording()
        let input = fixture.root.appendingPathComponent("tone.wav")
        try writeTone(.init(url: input, silentSeconds: 2))
        let recording = transcript([segment(.init(speaker: "a", start: 0, end: 4, confidence: 0.9))])
        let sample = try await SpeakerSampleBuilder.shared.make(.init(
            project: project(.init(fixture: fixture, audio: input)), transcript: recording, speakerID: "a"
        ))
        defer { try? FileManager.default.removeItem(at: sample.url) }
        XCTAssertEqual(sample.duration, 4, accuracy: 0.1)
        let file = try AVAudioFile(forReading: sample.url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        XCTAssertGreaterThan(samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count), 0.005)
        XCTAssertNoThrow(try AVAudioPlayer(contentsOf: sample.url))
    }

    func testSilentAudioDoesNotBecomeAVoiceSample() async throws {
        let fixture = try SyntheticRecording()
        let input = fixture.root.appendingPathComponent("silence.wav")
        try writeTone(.init(url: input, silentSeconds: 10))
        do {
            _ = try await SpeakerSampleBuilder.shared.make(.init(
                project: project(.init(fixture: fixture, audio: input)),
                transcript: transcript([segment(.init(speaker: "a", start: 0, end: 4, confidence: 0.9))]), speakerID: "a"
            ))
            XCTFail("Silence became a voice sample")
        } catch SpeakerVoiceStore.PreviewError.missingSample {
        }
    }

    @MainActor
    func testUnknownVoiceAssignmentExtendsExistingProfileAndSurvivesReload() async throws {
        let fixture = try SyntheticRecording()
        let input = fixture.root.appendingPathComponent("tone.wav")
        try writeTone(.init(url: input, silentSeconds: 0))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.take.projectURL)
        ) as? [String: Any])
        json["sources"] = [["role": "microphone", "path": input.path, "exists": true]]
        try JSONSerialization.data(withJSONObject: json).write(to: fixture.take.projectURL)

        let storeURL = fixture.root.appendingPathComponent("voices.json")
        let store = SpeakerVoiceStore(url: storeURL)
        let originalVoice = SpeakerVoice(embedding: [0, 1] + Array(repeating: 0, count: 254), duration: 8)
        let savedID = try await store.remember(.init(name: "Alice", voice: originalVoice, profileID: nil))
        let recording = transcript([segment(.init(speaker: "a", start: 0, end: 8, confidence: 0.9))])
        let entry = RecordingProjectHistory.Entry(
            id: UUID(), title: "Fixture call", projectPath: fixture.take.projectURL.path,
            takeDirectoryPath: fixture.take.scratchDirectory.path, finalVideoPath: nil,
            createdAt: Date(), updatedAt: Date(), exports: nil
        )
        var index = VoiceDiscoveryIndex()
        let profiles = try await store.profiles()
        index.include(.init(project: entry, transcript: recording, profiles: profiles))
        let candidate = try XCTUnwrap(index.voices.first)
        let model = VoiceDiscoveryModel(store: store)
        let previewURL = try await model.sampleURL(candidate)
        defer { try? FileManager.default.removeItem(at: previewURL) }

        let missingTarget = await model.save(.init(candidate: candidate, name: "Wrong name", profileID: UUID()))
        XCTAssertFalse(missingTarget)
        let afterFailure = try await store.profiles()
        XCTAssertEqual(afterFailure, profiles)

        let assigned = await model.save(.init(candidate: candidate, name: "Wrong name", profileID: savedID))
        XCTAssertTrue(assigned)
        let reloaded = SpeakerVoiceStore(url: storeURL)
        let saved = try await reloaded.profiles()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].id, savedID)
        XCTAssertEqual(saved[0].name, "Alice")
        XCTAssertEqual(saved[0].samples, [originalVoice, voice()])
        XCTAssertEqual(saved[0].preview?.sourceTitle, "Fixture call")
        let savedSampleURL = try await reloaded.sampleURL(for: savedID)
        let savedSample = try XCTUnwrap(savedSampleURL)
        XCTAssertNoThrow(try AVAudioPlayer(contentsOf: savedSample))
        var nextScan = VoiceDiscoveryIndex()
        nextScan.include(.init(project: entry, transcript: recording, profiles: saved))
        XCTAssertTrue(nextScan.voices.isEmpty)
        XCTAssertEqual(nextScan.knownCount, 1)
    }
}
