import CoreGraphics
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

    func testSceneAtInterpolatesDuringTransition() {
        var initialSettings = RecordingSettings()
        initialSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        initialSettings.canvasPadding = 0
        var changedSettings = initialSettings
        changedSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        changedSettings.canvasPadding = 0.1

        let scene = RecordingSceneTimeline.scene(
            at: 0.25,
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: changedSettings),
                    transition: RecordingSceneTransition(duration: 0.5, curve: .linear)
                )
            ],
            fallbackScene: RecordingScene(settings: initialSettings)
        )

        XCTAssertEqual(scene.sceneLayout.screenFrame.minY, 0.25, accuracy: 0.0001)
        XCTAssertEqual(scene.sceneLayout.screenFrame.height, 0.75, accuracy: 0.0001)
        XCTAssertEqual(scene.canvasPadding, 0.05, accuracy: 0.0001)
    }

    func testSceneAtCrossfadesSourceVisibilityDuringTransition() {
        var screenSettings = RecordingSettings()
        screenSettings.enabledSources = [.screen, .camera]
        screenSettings.hiddenSources = [.camera]
        screenSettings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)

        var cameraSettings = screenSettings
        cameraSettings.hiddenSources = [.screen]
        cameraSettings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)

        let scene = RecordingSceneTimeline.scene(
            at: 0.25,
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: cameraSettings),
                    transition: RecordingSceneTransition(duration: 0.5, curve: .linear)
                )
            ],
            fallbackScene: RecordingScene(settings: screenSettings)
        )

        XCTAssertEqual(scene.enabledSources, [.screen, .camera])
        XCTAssertEqual(scene.sourceOpacity(for: .screen), 0.5, accuracy: 0.0001)
        XCTAssertEqual(scene.sourceOpacity(for: .camera), 0.5, accuracy: 0.0001)
        XCTAssertEqual(scene.renderedSources, [.screen, .camera])
    }

    func testSceneAtUsesTargetLayerOrderDuringTransitionWithoutMidpointFlip() {
        var screenSettings = RecordingSettings()
        screenSettings.enabledSources = [.screen, .camera]
        screenSettings.hiddenSources = [.camera]
        screenSettings.sceneLayout = SceneLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            cameraFrame: CGRect(x: 0.6, y: 0.6, width: 0.35, height: 0.35),
            layerOrder: [.screen, .camera]
        )

        var cameraSettings = screenSettings
        cameraSettings.hiddenSources = [.screen]
        cameraSettings.sceneLayout.layerOrder = [.camera, .screen]

        let sceneEvents = [
            RecordingSceneEvent(
                time: 0,
                scene: RecordingScene(settings: cameraSettings),
                transition: RecordingSceneTransition(duration: 1, curve: .linear)
            )
        ]
        let fallbackScene = RecordingScene(settings: screenSettings)

        let firstTransitionFrame = RecordingSceneTimeline.scene(
            at: 1.0 / 60.0,
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene
        )
        let midpointFrame = RecordingSceneTimeline.scene(
            at: 0.5,
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene
        )

        XCTAssertEqual(firstTransitionFrame.sceneLayout.layerOrder, [.camera, .screen])
        XCTAssertEqual(midpointFrame.sceneLayout.layerOrder, [.camera, .screen])
        XCTAssertEqual(firstTransitionFrame.sourceOpacity(for: .camera), 1.0 / 60.0, accuracy: 0.0001)
    }

    func testSceneAtKeepsBackgroundStableUntilTransitionCompletes() {
        var initialSettings = RecordingSettings()
        initialSettings.canvasBackgroundStyle = .black
        initialSettings.canvasBackgroundAnimated = false
        var changedSettings = initialSettings
        changedSettings.canvasBackgroundStyle = .aurora
        changedSettings.canvasBackgroundAnimated = true

        let sceneEvents = [
            RecordingSceneEvent(
                time: 0,
                scene: RecordingScene(settings: changedSettings),
                transition: RecordingSceneTransition(duration: 1, curve: .linear)
            )
        ]
        let fallbackScene = RecordingScene(settings: initialSettings)

        let midpointFrame = RecordingSceneTimeline.scene(
            at: 0.5,
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene
        )
        let completedFrame = RecordingSceneTimeline.scene(
            at: 1,
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene
        )

        XCTAssertEqual(midpointFrame.canvasBackgroundStyle, .black)
        XCTAssertFalse(midpointFrame.canvasBackgroundAnimated)
        XCTAssertEqual(completedFrame.canvasBackgroundStyle, .aurora)
        XCTAssertTrue(completedFrame.canvasBackgroundAnimated)
    }

    func testRenderedSourcesExcludeTransparentTransitionSources() {
        let scene = RecordingScene(
            enabledSources: [.screen, .camera],
            sceneLayout: SceneLayout.defaultLayout(for: .vertical),
            sourceOpacities: [.camera: 0]
        )

        XCTAssertEqual(scene.renderedSources, [.screen])
    }

    func testSceneAtStartsLaterTransitionFromCurrentInterpolatedScene() {
        var initialSettings = RecordingSettings()
        initialSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        var firstTargetSettings = initialSettings
        firstTargetSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        var secondTargetSettings = initialSettings
        secondTargetSettings.sceneLayout.screenFrame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let scene = RecordingSceneTimeline.scene(
            at: 0.15,
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: firstTargetSettings),
                    transition: RecordingSceneTransition(duration: 0.5, curve: .linear)
                ),
                RecordingSceneEvent(
                    time: 0.1,
                    scene: RecordingScene(settings: secondTargetSettings),
                    transition: RecordingSceneTransition(duration: 0.5, curve: .linear)
                )
            ],
            fallbackScene: RecordingScene(settings: initialSettings)
        )

        XCTAssertEqual(scene.sceneLayout.screenFrame.minX, 0.025, accuracy: 0.0001)
        XCTAssertEqual(scene.sceneLayout.screenFrame.minY, 0.385, accuracy: 0.0001)
        XCTAssertEqual(scene.sceneLayout.screenFrame.width, 0.95, accuracy: 0.0001)
        XCTAssertEqual(scene.sceneLayout.screenFrame.height, 0.59, accuracy: 0.0001)
    }

    func testSegmentsSampleTransitionBoundaries() {
        var initialSettings = RecordingSettings()
        initialSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        var changedSettings = initialSettings
        changedSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let segments = RecordingSceneTimeline.segments(
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: changedSettings),
                    transition: RecordingSceneTransition(duration: 0.1, curve: .linear)
                )
            ],
            fallbackScene: RecordingScene(settings: initialSettings),
            duration: CMTime(seconds: 0.2, preferredTimescale: 600)
        )

        XCTAssertGreaterThan(segments.count, 2)
        XCTAssertTimeRange(segments[0].timeRange, startsAt: 0, duration: 1.0 / 60.0)
        XCTAssertEqual(segments[0].scene.sceneLayout.screenFrame.minY, 0.5, accuracy: 0.0001)
        XCTAssertEqual(segments.last?.scene.sceneLayout.screenFrame.minY ?? -1, 0, accuracy: 0.0001)
    }

    func testSegmentsSampleTransitionAtRequestedInterval() {
        var initialSettings = RecordingSettings()
        initialSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        var changedSettings = initialSettings
        changedSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let segments = RecordingSceneTimeline.segments(
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: changedSettings),
                    transition: RecordingSceneTransition(duration: 0.1, curve: .linear)
                )
            ],
            fallbackScene: RecordingScene(settings: initialSettings),
            duration: CMTime(seconds: 0.2, preferredTimescale: 600),
            transitionSampleInterval: 1.0 / 120.0
        )

        XCTAssertGreaterThan(segments.count, 10)
        XCTAssertTimeRange(segments[0].timeRange, startsAt: 0, duration: 1.0 / 120.0)
        XCTAssertEqual(segments[1].scene.sceneLayout.screenFrame.minY, 0.5 - (1.0 / 120.0 / 0.1 * 0.5), accuracy: 0.0001)
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
