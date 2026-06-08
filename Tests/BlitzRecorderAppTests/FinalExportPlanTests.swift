import CoreMedia
@testable import BlitzRecorderApp
import XCTest

final class FinalExportPlanTests: XCTestCase {
    func testPlanUsesOptimizedWriterForPlainCanvas() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.outputResolution = .p720

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [],
            sources: [source(.screen, duration: 1)]
        )

        XCTAssertEqual(plan.engine, .optimizedWriter)
        XCTAssertEqual(plan.renderSize, CGSize(width: 720, height: 1280))
        XCTAssertEqual(plan.duration.seconds, 1, accuracy: 0.0001)
    }

    func testPlanUsesAssetExportSessionForCanvasAwareSceneEvent() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        var changedSettings = settings
        changedSettings.canvasPadding = 0.08

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [RecordingSceneEvent(time: 0.2, scene: RecordingScene(settings: changedSettings))],
            sources: [source(.screen, duration: 1)]
        )

        XCTAssertEqual(plan.engine, .assetExportSession)
    }

    func testPlanOffsetsRemoteCameraInsertionWithoutExtendingCompositionDuration() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [],
            sources: [
                source(.screen, duration: 1),
                source(.camera, duration: 1, offset: 0.2)
            ]
        )
        let cameraInsertion = try XCTUnwrap(plan.insertion(for: .camera))

        XCTAssertEqual(plan.duration.seconds, 1, accuracy: 0.0001)
        XCTAssertEqual(cameraInsertion.sourceStart.seconds, 0, accuracy: 0.0001)
        XCTAssertEqual(cameraInsertion.compositionStart.seconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(cameraInsertion.duration.seconds, 0.8, accuracy: 0.0001)
        XCTAssertTrue(plan.renderSegments.contains { segment in
            segment.activeLayerOrder.contains(.camera)
        })
    }

    func testPlanTrimsNegativeSourceOffsetFromSourceStart() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [],
            sources: [source(.camera, duration: 1, offset: -0.2)]
        )
        let cameraInsertion = try XCTUnwrap(plan.insertion(for: .camera))

        XCTAssertEqual(plan.duration.seconds, 0.8, accuracy: 0.0001)
        XCTAssertEqual(cameraInsertion.sourceStart.seconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(cameraInsertion.compositionStart.seconds, 0, accuracy: 0.0001)
        XCTAssertEqual(cameraInsertion.duration.seconds, 0.8, accuracy: 0.0001)
    }

    func testPlanCanUseSourceRevealedBySceneEvent() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]
        var changedSettings = settings
        changedSettings.hiddenSources = []

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [RecordingSceneEvent(time: 0.2, scene: RecordingScene(settings: changedSettings))],
            sources: [source(.camera, duration: 1)]
        )

        XCTAssertEqual(plan.duration.seconds, 1, accuracy: 0.0001)
        XCTAssertNotNil(plan.insertion(for: .camera))
        XCTAssertTrue(plan.renderSegments.contains { segment in
            segment.activeLayerOrder.contains(.camera)
        })
    }

    func testPlanDoesNotInsertNeverVisibleSource() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [],
            sources: [
                source(.screen, duration: 1),
                source(.camera, duration: 1)
            ]
        )

        XCTAssertNotNil(plan.insertion(for: .screen))
        XCTAssertNil(plan.insertion(for: .camera))
        XCTAssertFalse(plan.renderSegments.contains { segment in
            segment.activeLayerOrder.contains(.camera)
        })
    }

    func testPlanKeepsCameraLayerWhenSourceFileCaptureTimelineIncludesCamera() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))],
            sources: [
                source(.screen, duration: 1),
                source(.camera, duration: 1)
            ]
        )

        XCTAssertNotNil(plan.insertion(for: .camera))
        XCTAssertTrue(plan.renderSegments.contains { segment in
            segment.activeLayerOrder.contains(.camera)
        })
    }

    func testPlanSamplesSceneTransitionsAtExportFrameRate() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.framesPerSecond = 60
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)

        var changedSettings = settings
        changedSettings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: changedSettings),
                    transition: RecordingSceneTransition(duration: 0.1, curve: .linear)
                )
            ],
            sources: [source(.screen, duration: 1)]
        )

        XCTAssertGreaterThan(plan.renderSegments.count, 6)
        XCTAssertEqual(plan.renderSegments[0].timeRange.duration.seconds, 1.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(plan.renderSegments[1].scene.sceneLayout.screenFrame.minY, 0.5 - (1.0 / 60.0 / 0.1 * 0.5), accuracy: 0.0001)
    }

    func testPlanKeepsFadingInSourceActiveOnFirstTransitionSegment() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.hiddenSources = [.camera]
        settings.framesPerSecond = 60
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)

        var changedSettings = settings
        changedSettings.hiddenSources = [.screen]
        changedSettings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)

        let plan = try FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: [
                RecordingSceneEvent(
                    time: 0,
                    scene: RecordingScene(settings: changedSettings),
                    transition: RecordingSceneTransition(duration: 0.35, curve: .easeInOut)
                )
            ],
            sources: [
                source(.screen, duration: 1),
                source(.camera, duration: 1)
            ]
        )

        XCTAssertEqual(plan.renderSegments[0].scene.sourceOpacity(for: .camera), 0, accuracy: 0.0001)
        XCTAssertTrue(plan.renderSegments[0].activeLayerOrder.contains(.camera))
        XCTAssertTrue(plan.renderSegments[0].activeLayerOrder.contains(.screen))
    }

    private func source(_ kind: SceneLayerKind, duration: Double, offset: Double = 0) -> FinalExportSourceInput {
        FinalExportSourceInput(
            kind: kind,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            timelineOffset: CMTime(seconds: offset, preferredTimescale: 600)
        )
    }
}
