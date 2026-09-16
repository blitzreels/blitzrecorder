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
        XCTAssertEqual(
            EditorTimelineZoom.stepped(.init(value: 1, duration: 88), factor: 1.5),
            EditorTimelineZoom.clamp(.init(value: 1.5, duration: 88))
        )
    }

    func testRulerShowsDistinctSubsecondLabelsAtHighZoom() {
        XCTAssertEqual(EditorTimelineRuler.interval(for: 2_000), 0.05)
        XCTAssertEqual(EditorTimelineRuler.label(.init(time: 60.05, interval: 0.05)), "01:00.05")
        XCTAssertEqual(EditorTimelineRuler.label(.init(time: 60.1, interval: 0.05)), "01:00.10")
        XCTAssertEqual(EditorTimelineRuler.label(.init(time: 1_700.5, interval: 0.5)), "28:20.5")
    }

    func testKeyboardZoomCommandsStepAndFit() {
        XCTAssertEqual(EditorTimelineZoom.applying(.zoomIn, value: 1, duration: 88), 1.5)
        XCTAssertEqual(EditorTimelineZoom.applying(.zoomOut, value: 1.5, duration: 88), 1)
        XCTAssertEqual(EditorTimelineZoom.applying(.fit, value: 8, duration: 88), 1)
        XCTAssertNil(EditorTimelineZoom.applying(.pause, value: 1, duration: 88))
    }

    func testKeyboardDispatchMapsPlaybackAndZoom() {
        XCTAssertEqual(
            EditorKeyboardDispatch.action(.ignore, zoom: 1, duration: 88),
            .ignore
        )
        XCTAssertEqual(
            EditorKeyboardDispatch.action(.showHelp, zoom: 1, duration: 88),
            .showHelp
        )
        XCTAssertEqual(
            EditorKeyboardDispatch.action(.command(.togglePlayback), zoom: 1, duration: 88),
            .togglePlayback
        )
        XCTAssertEqual(
            EditorKeyboardDispatch.action(.command(.seek(-3)), zoom: 1, duration: 88),
            .seekBy(-3)
        )
        XCTAssertEqual(
            EditorKeyboardDispatch.action(.command(.zoomIn), zoom: 1, duration: 88),
            .zoom(1.5)
        )
        XCTAssertEqual(
            EditorKeyboardDispatch.action(.command(.fit), zoom: 8, duration: 88),
            .zoom(1)
        )
    }
}
