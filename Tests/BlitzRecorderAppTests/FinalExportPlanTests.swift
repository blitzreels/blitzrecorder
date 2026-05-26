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
    }

    private func source(_ kind: SceneLayerKind, duration: Double, offset: Double = 0) -> FinalExportSourceInput {
        FinalExportSourceInput(
            kind: kind,
            duration: CMTime(seconds: duration, preferredTimescale: 600),
            timelineOffset: CMTime(seconds: offset, preferredTimescale: 600)
        )
    }
}
