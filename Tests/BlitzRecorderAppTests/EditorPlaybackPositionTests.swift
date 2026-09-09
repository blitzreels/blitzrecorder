import XCTest

@testable import BlitzRecorderApp

final class EditorPlaybackPositionTests: XCTestCase {
    func testTimeDisplayKeepsEditingPrecisionAndHandlesLongRecordings() {
        XCTAssertEqual(EditorPlaybackPosition.display(487.25), "08:07.25")
        XCTAssertEqual(EditorPlaybackPosition.display(3_661.5), "1:01:01.50")
        XCTAssertEqual(EditorPlaybackPosition.display(59.999), "01:00.00")
        XCTAssertEqual(EditorPlaybackPosition.display(.nan), "00:00.00")
        XCTAssertEqual(EditorPlaybackPosition.display(-1), "00:00.00")
    }

    func testJumpAcceptsSecondsMinutesHoursAndDecimalComma() {
        for text in ["487.25", "08:07.25", " 8:07,25 ", "0:08:07.25"] {
            XCTAssertEqual(EditorPlaybackPosition.parse(.init(text: text, duration: 1_978)), 487.25)
        }
        XCTAssertEqual(EditorPlaybackPosition.parse(.init(text: "1:01:01.5", duration: 4_000)), 3_661.5)
        XCTAssertEqual(EditorPlaybackPosition.parse(.init(text: "0", duration: 1_978)), 0)
        XCTAssertEqual(EditorPlaybackPosition.parse(.init(text: "32:58", duration: 1_978)), 1_978)
    }

    func testJumpRejectsInvalidAndOutOfBoundsTimes() {
        for text in ["", " ", "-1", "nan", "inf", "1e3", "1:60", "1:60:00", "1::2", ":5", "1.5:20", "32:59", "1:2:3:4"]
        {
            XCTAssertNil(EditorPlaybackPosition.parse(.init(text: text, duration: 1_978)), text)
        }
        XCTAssertNil(EditorPlaybackPosition.parse(.init(text: "1", duration: .infinity)))
        XCTAssertNil(EditorPlaybackPosition.parse(.init(text: "0", duration: 0)))
    }

    func testHomeAndEndPreserveSceneNavigationShortcuts() {
        XCTAssertEqual(EditorKeyboardCommand.resolve(.init(keyCode: 115, characters: "", modifiers: [])), .goToStart)
        XCTAssertEqual(EditorKeyboardCommand.resolve(.init(keyCode: 119, characters: "", modifiers: [])), .goToEnd)
        XCTAssertEqual(
            EditorKeyboardCommand.resolve(.init(keyCode: 126, characters: "", modifiers: [])), .previousBoundary)
        XCTAssertEqual(EditorKeyboardCommand.resolve(.init(keyCode: 125, characters: "", modifiers: [])), .nextBoundary)
        XCTAssertNil(EditorKeyboardCommand.resolve(.init(keyCode: 115, characters: "", modifiers: .shift)))
    }
}
