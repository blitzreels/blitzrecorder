import CoreMedia
@testable import BlitzRecorderApp
import XCTest

final class RecordingSceneTimelineTests: XCTestCase {
    func testSegmentsUseFallbackBeforeFirstSceneEvent() {
        var initialSettings = RecordingSettings()
        initialSettings.canvasBackgroundStyle = .black
        var changedSettings = initialSettings
        changedSettings.canvasBackgroundStyle = .aurora

        let segments = RecordingSceneTimeline.segments(
            sceneEvents: [
                RecordingSceneEvent(time: 0.5, scene: RecordingScene(settings: changedSettings))
            ],
            fallbackScene: RecordingScene(settings: initialSettings),
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertTimeRange(segments[0].timeRange, startsAt: 0, duration: 0.5)
        XCTAssertEqual(segments[0].scene.canvasBackgroundStyle, .black)
        XCTAssertTimeRange(segments[1].timeRange, startsAt: 0.5, duration: 0.5)
        XCTAssertEqual(segments[1].scene.canvasBackgroundStyle, .aurora)
    }

    func testSegmentsIncludeSourceTimeRangeBoundaries() {
        var settings = RecordingSettings()
        settings.canvasBackgroundStyle = .ocean
        let sourceRange = CMTimeRange(
            start: CMTime(seconds: 0.25, preferredTimescale: 600),
            duration: CMTime(seconds: 0.5, preferredTimescale: 600)
        )

        let segments = RecordingSceneTimeline.segments(
            sceneEvents: [],
            fallbackScene: RecordingScene(settings: settings),
            duration: CMTime(seconds: 1, preferredTimescale: 600),
            sourceTimeRanges: [sourceRange]
        )

        XCTAssertEqual(segments.count, 3)
        XCTAssertTimeRange(segments[0].timeRange, startsAt: 0, duration: 0.25)
        XCTAssertTimeRange(segments[1].timeRange, startsAt: 0.25, duration: 0.5)
        XCTAssertTimeRange(segments[2].timeRange, startsAt: 0.75, duration: 0.25)
    }

    func testCanvasAwareRenderingTracksFallbackAndEvents() {
        var settings = RecordingSettings()
        settings.canvasBackgroundStyle = .black
        settings.canvasPadding = 0
        var changedSettings = settings
        changedSettings.canvasPadding = 0.08

        XCTAssertFalse(RecordingSceneTimeline.requiresCanvasAwareRendering(settings: settings, sceneEvents: []))
        XCTAssertTrue(RecordingSceneTimeline.requiresCanvasAwareRendering(
            settings: settings,
            sceneEvents: [RecordingSceneEvent(time: 0.2, scene: RecordingScene(settings: changedSettings))]
        ))
    }
}

private func XCTAssertTimeRange(
    _ actual: CMTimeRange,
    startsAt expectedStart: Double,
    duration expectedDuration: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.start.seconds, expectedStart, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.duration.seconds, expectedDuration, accuracy: 0.0001, file: file, line: line)
}
