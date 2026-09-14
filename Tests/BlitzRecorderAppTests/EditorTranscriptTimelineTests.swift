import XCTest
@testable import BlitzRecorderApp

final class EditorTranscriptTimelineTests: XCTestCase {
    private func transcript() -> RecordingTranscript {
        RecordingTranscriptAssembler.assemble(.init(
            mediaPath: "/recording", generatedAt: Date(timeIntervalSince1970: 0), duration: 10,
            confidence: 0.95, text: "hello hello", suggestedTitle: nil,
            words: [
                .init(text: "hello", startTime: 1, endTime: 1.4, confidence: 0.95),
                .init(text: "hello", startTime: 1.7, endTime: 2.1, confidence: 0.95)
            ],
            diarizedIntervals: [.init(speakerID: "speaker", startTime: 0.9, endTime: 2.2)]
        ))
    }

    func testWordTimingsAndSpeechRangesSurviveSavingAndSpeakerMerge() throws {
        let original = transcript()
        let decoded = try JSONDecoder().decode(RecordingTranscript.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.words, original.words)
        XCTAssertEqual(decoded.speechRanges, original.speechRanges)
        let items = EditorTranscriptTimeline.items(.init(transcript: decoded, windows: [], threshold: -42, duration: 10))
        XCTAssertEqual(items.map(\.text), ["hello", "hello"])
        XCTAssertEqual(items.map(\.range), [.init(start: 1, end: 1.4), .init(start: 1.7, end: 2.1)])
        XCTAssertNotEqual(items[0].id, items[1].id)
    }

    func testLoudNonDialogueIsMarkedWithoutMarkingSpeechOrQuietGaps() {
        let items = EditorTranscriptTimeline.items(.init(
            transcript: transcript(), windows: [
                .init(start: 1.4, end: 1.6, decibels: -15),
                .init(start: 4, end: 4.2, decibels: -10),
                .init(start: 6, end: 7, decibels: -80)
            ], threshold: -42, duration: 10
        ))
        let sounds = items.filter { $0.kind == .nonDialogue }
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(sounds.first?.range.start ?? 0, 3.94, accuracy: 0.001)
        XCTAssertEqual(sounds.first?.range.end ?? 0, 4.26, accuracy: 0.001)
    }

    func testLegacyTranscriptShowsPhrasesWithoutInventingWordTimestamps() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(transcript())) as? [String: Any])
        payload.removeValue(forKey: "words")
        payload.removeValue(forKey: "speechRanges")
        let old = try JSONDecoder().decode(RecordingTranscript.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(old.words)
        let items = EditorTranscriptTimeline.items(.init(transcript: old, windows: [], threshold: -42, duration: 10))
        XCTAssertEqual(items.count, old.segments.count)
        XCTAssertTrue(items.allSatisfy { $0.kind == .phrase })
    }

    func testWordDeletionUsesExactTimelineRangeAndPreservesOtherWord() throws {
        let items = EditorTranscriptTimeline.items(.init(transcript: transcript(), windows: [], threshold: -42, duration: 10))
        let edited = try XCTUnwrap(EditorTimeRange.removing(.init(range: items[0].range, edits: .empty, takeDuration: 10)))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: edited.cuts)
        XCTAssertTrue(map.isRemoved(takeTime: 1.2))
        XCTAssertFalse(map.isRemoved(takeTime: 1.9))
        XCTAssertEqual(map.removedDuration, 0.4, accuracy: 0.002)
    }
}
