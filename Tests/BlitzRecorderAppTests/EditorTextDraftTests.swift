import XCTest
@testable import BlitzRecorderApp

final class EditorTextDraftTests: XCTestCase {
    func testNewOverlayStartsAtPlayheadAndClampsAtEndOfRecording() throws {
        let middle = try XCTUnwrap(TextOverlayEditing.newOverlay(.init(text: " A title ", preset: .title, time: 12, duration: 60)))
        XCTAssertEqual(middle.text, "A title")
        XCTAssertEqual(middle.start, 12)
        XCTAssertEqual(middle.end, 15)
        let end = try XCTUnwrap(TextOverlayEditing.newOverlay(.init(text: "End", preset: .title, time: 60, duration: 60)))
        XCTAssertEqual(end.end, 60)
        XCTAssertEqual(end.end - end.start, TextOverlayEditing.minimumLength, accuracy: 0.001)
        XCTAssertNil(TextOverlayEditing.newOverlay(.init(text: "   ", preset: .title, time: 5, duration: 6.6666667)))
    }

    func testEditingWordsPreservesExactTimingPositionStyleAndFade() throws {
        let original = TextOverlay(
            start: 1.234567, end: 5.765432, text: "Before",
            frame: CGRect(x: 0.2, y: 0.4, width: 0.5, height: 0.2),
            style: .init(preset: .title, size: 0.06, weight: .regular,
                         colorHex: "#FFCC00", background: .bar, alignment: .leading), fadeSeconds: 0.6
        )
        var expected = original
        expected.text = "After"
        XCTAssertEqual(TextOverlayEditing.retexted(.init(overlay: original, text: "After")), expected)
        XCTAssertNil(TextOverlayEditing.retexted(.init(overlay: original, text: "  ")))
        XCTAssertEqual(TextOverlayEditing.fading(.init(overlay: original, fades: false)).fadeSeconds, 0)
        XCTAssertEqual(TextOverlayEditing.fading(.init(overlay: original, fades: true)).fadeSeconds, 0.6)
        XCTAssertEqual(TextOverlayEditing.restyled(.init(overlay: original, preset: .title)), original)
    }

    func testSelectingAnotherStyleResetsOnlyTheStyleAndPosition() throws {
        let original = TextOverlay(start: 1, end: 4, text: "A title", frame: .zero, style: .title, fadeSeconds: 0)
        let result = TextOverlayEditing.restyled(.init(overlay: original, preset: .caption))
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.frame, TextOverlay.defaultFrame(for: .caption))
        XCTAssertEqual(result.style, .caption)
        XCTAssertEqual(result.fadeSeconds, 0)
        XCTAssertEqual(result.start, original.start)
        XCTAssertEqual(result.end, original.end)
    }
}
