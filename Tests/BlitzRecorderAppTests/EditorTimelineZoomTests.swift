import XCTest

@testable import BlitzRecorderApp

final class EditorTimelineZoomTests: XCTestCase {
    func testZoomExtendsBelowFitAndReachesHalfSecondOnLongRecordings() {
        XCTAssertEqual(EditorTimelineZoom.clamp(.init(value: 0.1, duration: 1_978)), 0.25)
        XCTAssertEqual(EditorTimelineZoom.maximum(for: 1_978), 3_956)
        XCTAssertEqual(1_978 / EditorTimelineZoom.maximum(for: 1_978), 0.5)
        XCTAssertGreaterThan(EditorTimelineZoom.maximum(for: 88), 12)
    }

    func testLogarithmicSliderRoundTripsAndDoublesAtEqualSteps() {
        for scale in [0.25, 0.5, 1, 2, 12, 128, 3_956] {
            let position = EditorTimelineZoom.sliderValue(.init(value: scale, duration: 1_978))
            XCTAssertEqual(EditorTimelineZoom.scale(.init(value: position, duration: 1_978)), scale, accuracy: 0.0001)
        }
        XCTAssertEqual(EditorTimelineZoom.scale(.init(value: 3, duration: 88)), 8)
        XCTAssertEqual(EditorTimelineZoom.scale(.init(value: 4, duration: 88)), 16)
    }

    func testZoomBoundsHandleInvalidAndVeryLongDurations() {
        XCTAssertEqual(EditorTimelineZoom.maximum(for: .nan), 16)
        XCTAssertEqual(EditorTimelineZoom.maximum(for: 0), 16)
        XCTAssertEqual(EditorTimelineZoom.maximum(for: 100_000), 16_384)
        XCTAssertEqual(EditorTimelineZoom.clamp(.init(value: .nan, duration: 88)), 1)
        XCTAssertEqual(EditorTimelineZoom.clamp(.init(value: 100_000, duration: 88)), 176)
    }

    func testRulerShowsDistinctSubsecondLabelsAtHighZoom() {
        XCTAssertEqual(EditorTimelineRuler.interval(for: 2_000), 0.05)
        XCTAssertEqual(EditorTimelineRuler.label(.init(time: 60.05, interval: 0.05)), "01:00.05")
        XCTAssertEqual(EditorTimelineRuler.label(.init(time: 60.1, interval: 0.05)), "01:00.10")
        XCTAssertEqual(EditorTimelineRuler.label(.init(time: 1_700.5, interval: 0.5)), "28:20.5")
    }
}
