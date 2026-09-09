import XCTest

@testable import BlitzRecorderApp

final class EditorPaneSizingTests: XCTestCase {
    func testInspectorBoundsPreservePreviewSpace() {
        let wide = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: 2_000, available: 1_200))
        XCTAssertEqual(wide.value, 640)
        let narrow = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: 2_000, available: 800))
        XCTAssertEqual(narrow.value, 432)
        XCTAssertGreaterThanOrEqual(800 - narrow.value - EditorPaneSizing.dividerSize, 360)
        XCTAssertEqual(EditorPaneSizing.resolve(.init(pane: .inspector, preferred: 0, available: 800)).value, 312)
    }

    func testTimelineBoundsLeaveSpaceForPreviewAndControls() {
        let expanded = EditorPaneSizing.resolve(.init(pane: .timeline, preferred: 900, available: 680))
        XCTAssertEqual(expanded.value, 472)
        XCTAssertEqual(680 - expanded.value - EditorPaneSizing.dividerSize, 200)
        let collapsed = EditorPaneSizing.resolve(.init(pane: .timeline, preferred: -50, available: 680))
        XCTAssertEqual(collapsed.value, 180)
    }

    func testTemporarilySmallWindowsDoNotLosePreferredSize() {
        let preferred = 500.0
        let small = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: preferred, available: 640))
        XCTAssertGreaterThan(small.value, 0)
        XCTAssertLessThan(small.value, 640 - EditorPaneSizing.dividerSize)
        XCTAssertEqual(small.bounds.lowerBound, small.bounds.upperBound)
        let restored = EditorPaneSizing.resolve(.init(pane: .inspector, preferred: preferred, available: 1_400))
        XCTAssertEqual(restored.value, preferred)
    }

    func testInvalidPreferencesAndTransientGeometryStayFinite() {
        XCTAssertEqual(EditorPaneSizing.resolve(.init(pane: .inspector, preferred: .nan, available: 1_200)).value, 360)
        XCTAssertEqual(
            EditorPaneSizing.resolve(.init(pane: .timeline, preferred: .infinity, available: 680)).value, 430)
        for available in [0.0, -1, .nan, .infinity] {
            let sizing = EditorPaneSizing.resolve(.init(pane: .timeline, preferred: 300, available: available))
            XCTAssertEqual(sizing.value, 0)
            XCTAssertEqual(sizing.bounds, 0...0)
        }
    }
}
