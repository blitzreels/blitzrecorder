import XCTest
@testable import BlitzRecorderApp

final class CaptionEditingRegressionTests: XCTestCase {
    private var source: TimelineEdits {
        var edits = TimelineEdits.empty
        edits.captions.isEnabled = true
        let words = ["Keep", "remove", "this", "please"].enumerated().map {
            TranscriptWord(text: $0.element, startTime: Double($0.offset), endTime: Double($0.offset + 1), confidence: 1)
        }
        edits.captions.cues = [.init(id: UUID(), start: 0, end: 4, text: CaptionGenerator.text(words), words: words)]
        edits.cuts = [.init(start: 1, end: 3, kind: .manual, source: .user)]
        return edits
    }

    func testTrimAndReopenKeepDeletedWordsOutOfCaptions() throws {
        let original = source
        let id = EditorPlacedItem.ID(kind: .caption, value: original.captions.cues[0].id)
        let trimmed = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: original,
            change: .init(id: id, timing: .init(start: 0.2, end: 3.8), gesture: .trimEnd))))
        let restored = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
            from: JSONEncoder().encode(RecordingProject.TimelineEditsSnapshot(trimmed))).edits
        let timeline = CaptionTimeline(.init(track: restored.captions, cuts: restored.enabledCuts))
        XCTAssertEqual(timeline.cue(at: 0.5)?.text, "Keep")
        XCTAssertNil(timeline.cue(at: 2))
        XCTAssertEqual(timeline.cue(at: 3.5)?.text, "please")
        XCTAssertNil(timeline.cue(at: 3.9))
        XCTAssertEqual(restored.captions.cues[0].words, original.captions.cues[0].words)
    }

    func testSplitPreservesWordMetadataAndDoesNotRestoreDeletedWords() throws {
        let original = source
        let split = try XCTUnwrap(EditorPlacedItemEditing.splitting(.init(edits: original,
            id: .init(kind: .caption, value: original.captions.cues[0].id), time: 2)))
        XCTAssertEqual(split.captions.cues.count, 2)
        XCTAssertTrue(split.captions.cues.allSatisfy { !$0.words.isEmpty })
        let timeline = CaptionTimeline(.init(track: split.captions, cuts: split.enabledCuts))
        XCTAssertEqual(timeline.cue(at: 0.5)?.text, "Keep")
        XCTAssertEqual(timeline.cue(at: 3.5)?.text, "please")
    }

    func testMoveOnlyCarriesWordsVisibleBeforeTheMove() throws {
        let original = source
        let moved = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: original,
            change: .init(id: .init(kind: .caption, value: original.captions.cues[0].id),
                timing: .init(start: 5, end: 7), gesture: .move))))
        let cue = try XCTUnwrap(moved.captions.cues.first)
        XCTAssertEqual(cue.text, "Keep please")
        XCTAssertEqual(cue.words.map(\.startTime), [5, 6])
        XCTAssertEqual(cue.words.map(\.endTime), [6, 7])
        let timeline = CaptionTimeline(.init(track: moved.captions, cuts: moved.enabledCuts))
        XCTAssertNil(timeline.cue(at: 0.5))
        XCTAssertEqual(timeline.cue(at: 6)?.text, "Keep please")
    }

    func testMoveAcrossDestinationCutKeepsWordsOnCorrectSidesOfTheSeam() throws {
        var original = source
        original.cuts = [.init(start: 6, end: 8, kind: .manual, source: .user)]
        original.captions.cues[0].end = 2
        let moved = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: original,
            change: .init(id: .init(kind: .caption, value: original.captions.cues[0].id),
                timing: .init(start: 5, end: 9), gesture: .move))))
        XCTAssertEqual(moved.captions.cues[0].words.map(\.startTime), [5, 8])
        XCTAssertEqual(moved.captions.cues[0].words.map(\.endTime), [6, 9])
        let timeline = CaptionTimeline(.init(track: moved.captions, cuts: moved.enabledCuts))
        XCTAssertEqual(timeline.cue(at: 5.5)?.text, "Keep")
        XCTAssertNil(timeline.cue(at: 7))
        XCTAssertEqual(timeline.cue(at: 8.5)?.text, "remove")
    }

    func testManualCaptionKeepsItsCorrectionWhenMovedAndSplit() throws {
        var original = source
        original.captions.cues[0].words = []
        original.captions.cues[0].text = "A manual correction"
        let id = EditorPlacedItem.ID(kind: .caption, value: original.captions.cues[0].id)
        let moved = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: original,
            change: .init(id: id, timing: .init(start: 5, end: 7), gesture: .move))))
        let split = try XCTUnwrap(EditorPlacedItemEditing.splitting(.init(edits: moved, id: id, time: 6)))
        XCTAssertEqual(split.captions.cues.map(\.text), ["A manual correction", "A manual correction"])
    }

    func testNestedOverlapsResumeEarlierCaptionsAndPreserveGaps() {
        var track = CaptionTrack.empty
        track.isEnabled = true
        track.cues = [
            .init(id: UUID(), start: 0, end: 10, text: "Earlier caption", words: []),
            .init(id: UUID(), start: 2, end: 7, text: "Middle caption", words: []),
            .init(id: UUID(), start: 3, end: 4, text: "Short caption", words: []),
            .init(id: UUID(), start: 11, end: 12, text: "After gap", words: [])
        ]
        let timeline = CaptionTimeline(.init(track: track, cuts: []))
        XCTAssertEqual(timeline.cue(at: 1)?.text, "Earlier caption")
        XCTAssertEqual(timeline.cue(at: 2)?.text, "Middle caption")
        XCTAssertEqual(timeline.cue(at: 3)?.text, "Short caption")
        XCTAssertEqual(timeline.cue(at: 4)?.text, "Middle caption")
        XCTAssertEqual(timeline.cue(at: 7)?.text, "Earlier caption")
        XCTAssertNil(timeline.cue(at: 10))
        XCTAssertEqual(timeline.cue(at: 11)?.text, "After gap")
        XCTAssertNil(timeline.cue(at: 12))
    }

    func testSameStartOverlapResumesLongerCaptionWithoutFillingCuts() {
        var track = CaptionTrack.empty
        track.isEnabled = true
        track.cues = [
            .init(id: UUID(), start: 0, end: 10, text: "Long", words: []),
            .init(id: UUID(), start: 0, end: 3, text: "Short", words: [])
        ]
        let timeline = CaptionTimeline(.init(track: track,
            cuts: [.init(start: 4, end: 6, kind: .manual, source: .user)]))
        XCTAssertEqual(timeline.cue(at: 1)?.text, "Short")
        XCTAssertEqual(timeline.cue(at: 3)?.text, "Long")
        XCTAssertNil(timeline.cue(at: 5))
        XCTAssertEqual(timeline.cue(at: 6)?.text, "Long")
    }
}
