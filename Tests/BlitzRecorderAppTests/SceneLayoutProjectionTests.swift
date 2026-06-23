import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class SceneLayoutProjectionTests: XCTestCase {
    func testDenormalizedLowerLeftOriginMatchesPreviewStageCanvas() {
        let frame = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let canvas = CGRect(x: 10, y: 20, width: 200, height: 400)

        let rect = SceneLayoutProjection.denormalized(frame, in: canvas, origin: .lowerLeft)

        XCTAssertEqual(rect, CGRect(x: 60, y: 220, width: 100, height: 100))
    }

    func testDenormalizedUpperLeftOriginMatchesExportCompositionPlacement() {
        let frame = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let canvas = CGRect(x: 10, y: 20, width: 200, height: 400)

        let rect = SceneLayoutProjection.denormalized(frame, in: canvas, origin: .upperLeft)

        XCTAssertEqual(rect, CGRect(x: 60, y: 120, width: 100, height: 100))
    }

    func testFrontToBackOrderPutsLastStoredLayerOnTop() {
        var layout = SceneLayout()
        layout.layerOrder = [.screen, .camera]

        XCTAssertEqual(SceneLayoutProjection.frontToBackOrder(for: layout), [.camera, .screen])
    }

    func testReorderedBackToFrontOrderPreservesDisplayedDropDirection() {
        var layout = SceneLayout()
        layout.layerOrder = [.screen, .camera]

        let order = SceneLayoutProjection.reorderedBackToFrontOrder(
            moving: .screen,
            onto: .camera,
            in: layout
        )

        XCTAssertEqual(order, [.camera, .screen])
    }

    func testSingleVideoSourceFillsCanvas() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.sceneLayout.cameraFrame = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

        let frame = SceneLayoutProjection.normalizedFrame(
            for: .camera,
            in: settings,
            fillsCanvasWhenOnlyVideoSource: true
        )

        XCTAssertEqual(frame, SceneLayoutProjection.fullFrame)
    }

    func testSceneLayoutGraphResolvesOnlyEnabledItemsInBackToFrontOrder() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.3)
        layout.layerOrder = [.camera, .screen]

        let items = layout.resolvedItems(
            enabledSources: [.screen, .camera],
            fillsCanvasWhenOnlyVideoSource: true
        )

        XCTAssertEqual(items.map(\.kind), [.camera, .screen])
        XCTAssertEqual(items[0].normalizedFrame, layout.cameraFrame)
        XCTAssertEqual(items[1].normalizedFrame, layout.screenFrame)
    }

    func testSceneLayoutGraphExpandsSingleVisibleVideoItem() {
        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.3)

        let items = layout.resolvedItems(
            enabledSources: [.camera],
            fillsCanvasWhenOnlyVideoSource: true
        )

        XCTAssertEqual(items, [
            ResolvedSceneLayoutItem(kind: .camera, normalizedFrame: SceneLayoutProjection.fullFrame)
        ])
    }

    func testPaddedRectUsesShortestCanvasEdge() {
        let canvas = CGRect(x: 0, y: 0, width: 100, height: 200)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 200)

        let padded = SceneLayoutProjection.padded(rect, in: canvas, padding: 0.1)

        XCTAssertEqual(padded, CGRect(x: 10, y: 10, width: 80, height: 180))
    }

    func testProjectedFrameAppliesSingleVideoSourcePaddingFromFullCanvas() {
        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let canvas = CGRect(x: 0, y: 0, width: 100, height: 200)

        let frame = SceneLayoutProjection.projectedFrame(
            for: .camera,
            in: canvas,
            sceneLayout: layout,
            enabledSources: [.camera],
            canvasPadding: 0.1,
            origin: .lowerLeft,
            fillsCanvasWhenOnlyVideoSource: true
        )

        XCTAssertEqual(frame, CGRect(x: 10, y: 10, width: 80, height: 180))
    }

    func testSceneRenderGeometryUsesRecordingSceneVisibility() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.canvasPadding = 0.1
        settings.sceneLayout.cameraFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let scene = RecordingScene(settings: settings)
        let canvas = CGRect(x: 0, y: 0, width: 100, height: 200)

        let frame = SceneRenderGeometry(
            canvas: canvas,
            scene: scene,
            origin: .upperLeft
        ).targetRect(for: .camera)

        XCTAssertRect(frame, equals: CGRect(x: 26, y: 86, width: 32, height: 64))
        XCTAssertEqual(frame.width / frame.height, 0.5, accuracy: 0.0001)
    }

    func testSceneRenderGeometryOwnsActiveLayerOrderAndSourceMask() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.canvasPadding = 0.1
        settings.hiddenSources = [.screen]
        settings.sceneLayout.layerOrder = [.screen, .camera]
        let geometry = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 100, height: 100),
            scene: RecordingScene(settings: settings),
            origin: .upperLeft
        )

        XCTAssertEqual(geometry.activeLayerOrder, [.camera])
        XCTAssertNotNil(geometry.sourceMaskPath())
    }

}

private func XCTAssertRect(
    _ actual: CGRect,
    equals expected: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, file: file, line: line)
}
