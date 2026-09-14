import Foundation
import XCTest
@testable import BlitzRecorderApp

final class RecordingTranscriptTests: XCTestCase {
    func testDownloadsLocalModelsWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_TEST_MODEL_DOWNLOAD"] == "1" else {
            throw XCTSkip("Set BLITZRECORDER_TEST_MODEL_DOWNLOAD=1 to download and validate local models.")
        }

        let engine = LocalTranscriptionEngine()
        try await engine.downloadModels(
            LocalTranscriptionEngine.DownloadRequest { _ in }
        )

        XCTAssertTrue(LocalTranscriptionModelStore().isInstalled)
    }

    func testTranscribesProjectWhenExplicitlyEnabled() async throws {
        guard let projectPath = ProcessInfo.processInfo
            .environment["BLITZRECORDER_TEST_TRANSCRIBE_PROJECT"] else {
            throw XCTSkip("Set BLITZRECORDER_TEST_TRANSCRIBE_PROJECT to a project file.")
        }

        let engine = LocalTranscriptionEngine()
        let transcript = try await engine.transcribe(
            LocalTranscriptionEngine.TranscribeRequest(
                source: .project(URL(fileURLWithPath: projectPath)),
                onUpdate: { _ in }
            )
        )

        XCTAssertFalse(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(transcript.segments.isEmpty)
        XCTAssertFalse(transcript.speakers.isEmpty)
        XCTAssertGreaterThan(transcript.duration, 0)
        XCTAssertTrue((transcript.words ?? []).allSatisfy { $0.endTime <= transcript.duration + 0.1 })
    }

    func testAssemblerCreatesChronologicalSpeakerSegments() {
        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: "/tmp/recording.mov",
                generatedAt: Date(timeIntervalSince1970: 1_000),
                duration: 4,
                confidence: 0.91,
                text: "Hello there. Hi Karim.",
                suggestedTitle: "client-interview",
                words: [
                    TranscriptWord(
                        text: "Hello",
                        startTime: 0.1,
                        endTime: 0.4,
                        confidence: 0.9
                    ),
                    TranscriptWord(
                        text: "there.",
                        startTime: 0.5,
                        endTime: 0.9,
                        confidence: 0.88
                    ),
                    TranscriptWord(
                        text: "Hi",
                        startTime: 2,
                        endTime: 2.2,
                        confidence: 0.94
                    ),
                    TranscriptWord(
                        text: "Karim.",
                        startTime: 2.3,
                        endTime: 2.8,
                        confidence: 0.93
                    ),
                ],
                diarizedIntervals: [
                    DiarizedInterval(
                        speakerID: "raw-a",
                        startTime: 0,
                        endTime: 1.2
                    ),
                    DiarizedInterval(
                        speakerID: "raw-b",
                        startTime: 1.8,
                        endTime: 3
                    ),
                ]
            )
        )

        XCTAssertEqual(transcript.speakers.map(\.id), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(transcript.segments.count, 2)
        XCTAssertEqual(transcript.segments[0].speakerID, "Speaker 1")
        XCTAssertEqual(transcript.segments[0].text, "Hello there.")
        XCTAssertEqual(transcript.segments[1].speakerID, "Speaker 2")
        XCTAssertEqual(transcript.segments[1].text, "Hi Karim.")
        XCTAssertEqual(transcript.wordCount, 4)
        XCTAssertEqual(transcript.segmentCount, 2)
        XCTAssertEqual(transcript.speakerCount, 2)
        XCTAssertEqual(transcript.wordsPerMinute, 60)
        XCTAssertEqual(transcript.wordCount(for: "Speaker 1"), 2)
        XCTAssertEqual(transcript.wordCount(for: "Speaker 2"), 2)
        XCTAssertEqual(
            transcript.speakingDuration(for: "Speaker 1"),
            0.8,
            accuracy: 0.001
        )
        XCTAssertTrue(transcript.formattedText.contains("[00:00] Speaker 1"))
        XCTAssertTrue(transcript.formattedText.contains("[00:02] Speaker 2"))
        XCTAssertTrue(transcript.markdownText.contains("# client-interview"))
        XCTAssertTrue(transcript.markdownText.contains("## Transcript"))
        XCTAssertTrue(transcript.markdownText.contains("**[00:00] Speaker 1:**"))
    }

    func testMarkdownTranscriptIncludesSpeakerNamesAndContext() {
        let transcript = RecordingTranscript(
            version: 1,
            id: UUID(),
            mediaPath: "/tmp/demo.mov",
            generatedAt: Date(timeIntervalSince1970: 1_000),
            duration: 3,
            confidence: 0.9,
            text: "Hello",
            suggestedTitle: "Demo *call*",
            speakers: [
                RecordingTranscript.Speaker(
                    id: "Speaker 1",
                    name: "Alex",
                    context: "Host"
                )
            ],
            segments: [
                RecordingTranscript.Segment(
                    id: UUID(),
                    speakerID: "Speaker 1",
                    startTime: 1,
                    endTime: 2,
                    text: "Hello",
                    confidence: 0.9
                )
            ]
        )

        XCTAssertTrue(transcript.markdownText.contains("# Demo \\*call\\*"))
        XCTAssertTrue(transcript.markdownText.contains("- **Alex** — Host"))
        XCTAssertTrue(transcript.markdownText.contains("**[00:01] Alex:** Hello"))
        XCTAssertTrue(
            transcript.markdownText(title: "Visible project title")
                .hasPrefix("# Visible project title")
        )
    }

    func testAssemblerAssignsBoundaryWordToNearestSpeakerInterval() {
        let wordTexts = [
            "Bon",
            "là",
            "je",
            "fais",
            "un",
            "petit",
            "essai",
            "pour",
            "voir",
            "si",
            "ça",
            "fonctionne.",
        ]
        let words = wordTexts.enumerated().map { indexedWord in
            let (index, text) = indexedWord
            let startTime = index == 0 ? 0.4 : 0.8 + Double(index - 1) * 0.25
            return TranscriptWord(
                text: text,
                startTime: startTime,
                endTime: startTime + (index == 0 ? 0.32 : 0.2),
                confidence: 0.99
            )
        }
        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: "/tmp/solo-recording.mov",
                generatedAt: Date(timeIntervalSince1970: 3_000),
                duration: 3.6,
                confidence: 0.99,
                text: wordTexts.joined(separator: " "),
                suggestedTitle: nil,
                words: words,
                diarizedIntervals: [
                    DiarizedInterval(
                        speakerID: "dominant-cluster",
                        startTime: 0.8,
                        endTime: 3.5
                    ),
                ]
            )
        )

        XCTAssertEqual(transcript.speakerCount, 1)
        XCTAssertEqual(transcript.segmentCount, 1)
        XCTAssertEqual(transcript.segments[0].speakerID, "Speaker 1")
        XCTAssertEqual(transcript.segments[0].text, wordTexts.joined(separator: " "))
    }

    func testAssemblerCollapsesTinyFragmentSpeakerCluster() {
        var words: [TranscriptWord] = []
        var intervals: [DiarizedInterval] = []

        for index in 0..<100 {
            let startTime = Double(index)
            words.append(TranscriptWord(
                text: "word\(index)",
                startTime: startTime,
                endTime: startTime + 0.4,
                confidence: 0.95
            ))
            intervals.append(DiarizedInterval(
                speakerID: "dominant",
                startTime: startTime,
                endTime: startTime + 0.8
            ))
        }

        for index in [20, 70] {
            let startTime = Double(index) + 0.82
            words.append(TranscriptWord(
                text: "okay",
                startTime: startTime,
                endTime: startTime + 0.18,
                confidence: 0.9
            ))
            intervals.append(DiarizedInterval(
                speakerID: "fragment",
                startTime: startTime,
                endTime: startTime + 0.2
            ))
        }

        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: "/tmp/solo-recording.mov",
                generatedAt: Date(timeIntervalSince1970: 4_000),
                duration: 100,
                confidence: 0.95,
                text: words.map(\.text).joined(separator: " "),
                suggestedTitle: nil,
                words: words,
                diarizedIntervals: intervals
            )
        )

        XCTAssertEqual(transcript.speakerCount, 1)
        XCTAssertEqual(Set(transcript.segments.map(\.speakerID)), ["Speaker 1"])
    }

    func testSpeakerAssignmentsPersistInJSONAndText() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let locations = TranscriptArtifactStore.Locations(
            jsonURL: directory.appendingPathComponent("transcript.json"),
            textURL: directory.appendingPathComponent("transcript.txt")
        )
        var transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: "/tmp/recording.mov",
                generatedAt: Date(timeIntervalSince1970: 2_000),
                duration: 2,
                confidence: 0.9,
                text: "Good morning",
                suggestedTitle: nil,
                words: [
                    TranscriptWord(
                        text: "Good",
                        startTime: 0,
                        endTime: 0.3,
                        confidence: 0.9
                    ),
                    TranscriptWord(
                        text: "morning",
                        startTime: 0.4,
                        endTime: 0.8,
                        confidence: 0.9
                    ),
                ],
                diarizedIntervals: []
            )
        )
        transcript.speakers[0].name = "Sarah"
        transcript.speakers[0].context = "Acme"

        let store = TranscriptArtifactStore()
        try store.save(TranscriptArtifactStore.SaveRequest(
            transcript: transcript,
            locations: locations
        ))

        let reloaded = try store.load(from: locations.jsonURL)
        XCTAssertEqual(reloaded.speakers[0].name, "Sarah")
        XCTAssertEqual(reloaded.speakers[0].context, "Acme")
        XCTAssertTrue(
            try String(contentsOf: locations.textURL, encoding: .utf8)
                .contains("Sarah: Good morning")
        )
    }

    func testAssemblerMergesAcousticDuplicateSpeakers() {
        let micVoice: [Float] = [0.98, 0.02, 0.10, 0.15]
        let echoedVoice: [Float] = [0.95, 0.05, 0.14, 0.20]
        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: "/tmp/echo.mov",
                generatedAt: Date(timeIntervalSince1970: 5_000),
                duration: 4,
                confidence: 0.9,
                text: "Hello there. Still me.",
                suggestedTitle: nil,
                words: [
                    TranscriptWord(text: "Hello", startTime: 0.1, endTime: 0.4, confidence: 0.9),
                    TranscriptWord(text: "there.", startTime: 0.5, endTime: 0.9, confidence: 0.9),
                    TranscriptWord(text: "Still", startTime: 2, endTime: 2.3, confidence: 0.9),
                    TranscriptWord(text: "me.", startTime: 2.4, endTime: 2.8, confidence: 0.9),
                ],
                diarizedIntervals: [
                    DiarizedInterval(
                        speakerID: "mic-cluster",
                        startTime: 0,
                        endTime: 1.2,
                        embedding: micVoice
                    ),
                    DiarizedInterval(
                        speakerID: "system-cluster",
                        startTime: 1.8,
                        endTime: 3,
                        embedding: echoedVoice
                    ),
                ]
            )
        )

        XCTAssertEqual(transcript.speakerCount, 1)
        XCTAssertEqual(transcript.speakers.map(\.id), ["Speaker 1"])
    }

    func testAssemblerKeepsDistinctSpeakersSeparate() {
        let alice: [Float] = [0.98, 0.02, 0.10, 0.15]
        let bob: [Float] = [0.05, 0.97, 0.90, 0.12]
        let transcript = RecordingTranscriptAssembler.assemble(
            RecordingTranscriptAssembler.Request(
                mediaPath: "/tmp/two.mov",
                generatedAt: Date(timeIntervalSince1970: 6_000),
                duration: 4,
                confidence: 0.9,
                text: "Hello there. Hi Karim.",
                suggestedTitle: nil,
                words: [
                    TranscriptWord(text: "Hello", startTime: 0.1, endTime: 0.4, confidence: 0.9),
                    TranscriptWord(text: "there.", startTime: 0.5, endTime: 0.9, confidence: 0.9),
                    TranscriptWord(text: "Hi", startTime: 2, endTime: 2.2, confidence: 0.9),
                    TranscriptWord(text: "Karim.", startTime: 2.3, endTime: 2.8, confidence: 0.9),
                ],
                diarizedIntervals: [
                    DiarizedInterval(
                        speakerID: "raw-a",
                        startTime: 0,
                        endTime: 1.2,
                        embedding: alice
                    ),
                    DiarizedInterval(
                        speakerID: "raw-b",
                        startTime: 1.8,
                        endTime: 3,
                        embedding: bob
                    ),
                ]
            )
        )

        XCTAssertEqual(transcript.speakerCount, 2)
        XCTAssertEqual(transcript.speakers.map(\.id), ["Speaker 1", "Speaker 2"])
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
