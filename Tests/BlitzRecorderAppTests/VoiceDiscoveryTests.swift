import XCTest
@testable import BlitzRecorderApp

final class VoiceDiscoveryTests: XCTestCase {
    private func voice(_ components: [Float]) -> SpeakerVoice {
        .init(embedding: components + Array(repeating: 0, count: 256 - components.count), duration: 8)
    }

    private func transcript(_ voices: [SpeakerVoice]) -> RecordingTranscript {
        .init(version: 2, id: UUID(), mediaPath: "/fixture.mov", generatedAt: Date(), duration: 100,
              confidence: 0.9, text: "Hello", suggestedTitle: nil,
              speakers: voices.enumerated().map { .init(id: "\($0.offset)", name: "", context: "", voice: $0.element) },
              segments: voices.enumerated().map {
                  .init(id: UUID(), speakerID: "\($0.offset)", startTime: Double($0.offset * 10),
                        endTime: Double($0.offset * 10 + 8), text: "Hello", confidence: 0.9)
              })
    }

    private func entry(_ fixture: SyntheticRecording) -> RecordingProjectHistory.Entry {
        .init(id: UUID(), title: "Fixture", projectPath: fixture.take.projectURL.path,
              takeDirectoryPath: fixture.take.scratchDirectory.path, finalVideoPath: nil,
              createdAt: Date(), updatedAt: Date(), exports: nil)
    }

    func testSavedVoicesAreExcludedAndUnknownVoicesGroupedAcrossRecordings() throws {
        let first = try SyntheticRecording()
        let second = try SyntheticRecording()
        let known = SavedSpeakerVoice(id: UUID(), name: "Alice", samples: [voice([1, 0])])
        var index = VoiceDiscoveryIndex()
        index.include(.init(project: entry(first), transcript: transcript([voice([1, 0]), voice([0, 1])]), profiles: [known]))
        index.include(.init(project: entry(second), transcript: transcript([voice([0.02, 1])]), profiles: [known]))
        XCTAssertEqual(index.knownCount, 1)
        XCTAssertEqual(index.voices.count, 1)
        XCTAssertEqual(index.voices[0].recordingCount, 2)
    }

    func testTwoSpeakersInOneRecordingAreNotCollapsedIntoOneCandidate() throws {
        let fixture = try SyntheticRecording()
        var index = VoiceDiscoveryIndex()
        index.include(.init(project: entry(fixture), transcript: transcript([voice([1, 0]), voice([1, 0.01])]), profiles: []))
        XCTAssertEqual(index.voices.count, 2)
    }

    func testAmbiguousCandidateDoesNotJoinEitherExistingGroup() throws {
        let fixtures = try (0..<3).map { _ in try SyntheticRecording() }
        var index = VoiceDiscoveryIndex()
        for (fixture, sample) in zip(fixtures, [voice([1, 0]), voice([0.6, 0.8]), voice([0.9, 0.45])]) {
            index.include(.init(project: entry(fixture), transcript: transcript([sample]), profiles: []))
        }
        XCTAssertEqual(index.voices.count, 3)
    }

    func testShortSpeechAndSegmentsWithoutClearPreviewAreNotOffered() throws {
        let fixture = try SyntheticRecording()
        var index = VoiceDiscoveryIndex()
        var recording = transcript([voice([1, 0])])
        recording.speakers[0].voice = .init(embedding: voice([1, 0]).embedding, duration: 1)
        index.include(.init(project: entry(fixture), transcript: recording, profiles: []))
        let noSegments = RecordingTranscript(version: 2, id: UUID(), mediaPath: "/fixture", generatedAt: Date(),
            duration: 10, confidence: 0.9, text: "", suggestedTitle: nil,
            speakers: transcript([voice([1, 0])]).speakers, segments: [])
        index.include(.init(project: entry(fixture), transcript: noSegments, profiles: []))
        XCTAssertTrue(index.voices.isEmpty)
        XCTAssertEqual(index.insufficientCount, 2)
    }

    func testExplicitSavedLinkIsRespectedEvenWhenVoiceSoundsDifferent() throws {
        let fixture = try SyntheticRecording()
        let profile = SavedSpeakerVoice(id: UUID(), name: "Alice", samples: [voice([1, 0])])
        var recording = transcript([voice([0, 1])])
        recording.speakers[0].savedVoiceID = profile.id
        var index = VoiceDiscoveryIndex()
        index.include(.init(project: entry(fixture), transcript: recording, profiles: [profile]))
        XCTAssertTrue(index.voices.isEmpty)
        XCTAssertEqual(index.knownCount, 1)
    }

    func testAudioOnlyAnalysisPreservesTimingAndCollectsVoiceWithoutInventingWords() {
        let recording = VoiceDiscoveryAnalysis.transcript(.init(intervals: [
            .init(speakerID: "mic-0", startTime: 1, endTime: 5, embedding: voice([1, 0]).embedding),
            .init(speakerID: "mic-0", startTime: 5, endTime: 9, embedding: voice([1, 0]).embedding),
            .init(speakerID: "sys-1", startTime: 11, endTime: 17, embedding: voice([0, 1]).embedding),
            .init(speakerID: "invalid", startTime: .nan, endTime: 19, embedding: voice([0, 1]).embedding)
        ], mediaPath: "/fixture", duration: 15))
        XCTAssertEqual(recording.speakers.count, 2)
        XCTAssertTrue(recording.text.isEmpty)
        XCTAssertNil(recording.words)
        XCTAssertEqual(recording.segments.map(\.startTime), [1, 11])
        XCTAssertEqual(recording.segments.map(\.endTime), [9, 15])
        XCTAssertTrue(recording.speakers.allSatisfy { $0.voice?.isUsable == true })
    }

    private actor Capture {
        var updates: [VoiceDiscoveryScanner.Update] = []
        var analyses = 0
        func append(_ update: VoiceDiscoveryScanner.Update) { updates.append(update) }
        func analyzed() { analyses += 1 }
        func last() -> VoiceDiscoveryScanner.Update? { updates.last }
        func count() -> Int { analyses }
    }

    func testScanUsesExistingTranscriptWithoutWritingOrRunningAnalysis() async throws {
        let fixture = try SyntheticRecording()
        let project = try TakeFileStore().loadRecordingProject(at: fixture.take.projectURL)
        let artifacts = TranscriptArtifactStore()
        let locations = artifacts.locations(for: project)
        try artifacts.save(.init(transcript: transcript([voice([1, 0])]), locations: locations))
        let before = try Data(contentsOf: locations.jsonURL)
        let capture = Capture()
        let scanner = VoiceDiscoveryScanner(configuration: .init(cacheDirectory: fixture.root.appendingPathComponent("cache"),
            analyze: { _ in XCTFail("Existing voice analysis should be reused"); throw LocalTranscriptionError.transcriptUnavailable }))
        let projectEntry = entry(fixture)
        try await scanner.scan(.init(projects: [projectEntry, projectEntry], profiles: [], onUpdate: { await capture.append($0) }))
        let update = await capture.last()
        XCTAssertEqual(update?.index.voices.count, 1)
        XCTAssertEqual(update?.checked, 1)
        XCTAssertEqual(update?.total, 1)
        XCTAssertEqual(try Data(contentsOf: locations.jsonURL), before)
    }

    func testMissingAnalysisIsCachedAndInvalidatedWhenSourceChanges() async throws {
        let fixture = try SyntheticRecording()
        let capture = Capture()
        let recording = transcript([voice([1, 0])])
        let scanner = VoiceDiscoveryScanner(configuration: .init(cacheDirectory: fixture.root.appendingPathComponent("cache"),
            analyze: { _ in await capture.analyzed(); return recording }))
        let request = VoiceDiscoveryScanner.Request(projects: [entry(fixture)], profiles: [], onUpdate: { await capture.append($0) })
        try await scanner.scan(request)
        try await scanner.scan(request)
        let countBeforeChange = await capture.count()
        XCTAssertEqual(countBeforeChange, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.take.scratchDirectory.appendingPathComponent("transcript.json").path))
        try Data([1, 2, 3]).write(to: fixture.take.screenURL)
        try await scanner.scan(request)
        let countAfterChange = await capture.count()
        XCTAssertEqual(countAfterChange, 2)
    }

    func testUnreadableRecordingDoesNotStopRemainingRecordings() async throws {
        let fixture = try SyntheticRecording()
        let capture = Capture()
        let recording = transcript([voice([1, 0])])
        let missing = RecordingProjectHistory.Entry(id: UUID(), title: "Missing", projectPath: "/missing/project.json",
            takeDirectoryPath: "/missing", finalVideoPath: nil, createdAt: nil, updatedAt: Date(), exports: nil)
        let scanner = VoiceDiscoveryScanner(configuration: .init(cacheDirectory: fixture.root.appendingPathComponent("cache"),
            analyze: { _ in recording }))
        try await scanner.scan(.init(projects: [missing, entry(fixture)], profiles: [], onUpdate: { await capture.append($0) }))
        let update = await capture.last()
        XCTAssertEqual(update?.failures.count, 1)
        XCTAssertEqual(update?.index.voices.count, 1)
        XCTAssertEqual(update?.checked, 2)
    }

    func testCancellationDoesNotPublishOrCacheIncompleteAnalysis() async throws {
        let fixture = try SyntheticRecording()
        let capture = Capture()
        let cache = fixture.root.appendingPathComponent("cache")
        let scanner = VoiceDiscoveryScanner(configuration: .init(cacheDirectory: cache, analyze: { _ in throw CancellationError() }))
        do {
            try await scanner.scan(.init(projects: [entry(fixture)], profiles: [], onUpdate: { await capture.append($0) }))
            XCTFail("Cancelled scan completed")
        } catch is CancellationError {
        }
        let update = await capture.last()
        XCTAssertEqual(update?.checked, 0)
        XCTAssertTrue(update?.index.voices.isEmpty == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }
}
