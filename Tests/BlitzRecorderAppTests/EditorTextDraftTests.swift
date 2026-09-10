import XCTest
@testable import BlitzRecorderApp

final class EditorTextDraftTests: XCTestCase {
    func testTimingAcceptsTimecodesAndLocalizedSecondsAndRejectsInvalidRanges() throws {
        var draft = EditorTextDraft()
        draft.text = "A title"
        draft.startText = "1:02.25"
        draft.endText = "65,75"
        XCTAssertEqual(draft.range(90), .init(start: 62.25, end: 65.75))
        for invalid in ["00:90", "-2", "no", "91", "62.25"] {
            draft.endText = invalid
            XCTAssertNil(draft.overlay(90))
        }
    }

    func testPlayheadKeepsDurationAndClampsAtEndOfRecording() throws {
        var draft = EditorTextDraft()
        draft.moveToPlayhead(.init(time: 12, duration: 60))
        XCTAssertEqual(draft.range(60), .init(start: 12, end: 15))
        draft.moveToPlayhead(.init(time: 59, duration: 60))
        XCTAssertEqual(draft.range(60), .init(start: 59, end: 60))
        draft.moveToPlayhead(.init(time: 60, duration: 60))
        XCTAssertEqual(try XCTUnwrap(draft.range(60)).duration, 0.1, accuracy: 0.001)
    }

    func testEditingWordsPreservesExactTimingPositionStyleAndFade() throws {
        let original = TextOverlay(
            start: 1.234567, end: 5.765432, text: "Before",
            frame: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.2),
            style: .init(preset: .title, size: 0.06, weight: .regular,
                         colorHex: "#FFCC00", background: .bar, alignment: .leading), fadeSeconds: 0.6
        )
        var draft = EditorTextDraft()
        draft.edit(original)
        draft.text = "After"
        var expected = original
        expected.text = "After"
        XCTAssertEqual(try XCTUnwrap(draft.overlay(10)), expected)
        draft.fades = false
        XCTAssertEqual(draft.overlay(10)?.fadeSeconds, 0)
        draft.fades = true
        XCTAssertEqual(draft.overlay(10)?.fadeSeconds, original.fadeSeconds)
    }

    func testSelectingAnotherStyleResetsOnlyTheStyleAndPosition() throws {
        let original = TextOverlay(start: 1, end: 4, text: "A title", frame: .zero, style: .title, fadeSeconds: 0)
        var draft = EditorTextDraft()
        draft.edit(original)
        draft.preset = .caption
        let result = try XCTUnwrap(draft.overlay(10))
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.frame, TextOverlay.defaultFrame(for: .caption))
        XCTAssertEqual(result.style, .caption)
        XCTAssertEqual(result.fadeSeconds, 0)
        XCTAssertEqual(result.start, original.start)
        XCTAssertEqual(result.end, original.end)
    }

    func testRoundedRecordingEndRemainsAValidInsertionPoint() throws {
        var draft = EditorTextDraft()
        draft.moveToPlayhead(.init(time: 5, duration: 6.6666667))
        XCTAssertEqual(try XCTUnwrap(draft.range(6.6666667)).end, 6.6666667)
        draft.text = "   "
        XCTAssertNil(draft.overlay(6.6666667))
    }
}
