import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class PreviewStageEditingTests: XCTestCase {
    func testHitTestingUsesFrontToBackSceneOrder() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layout.cameraFrame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        layout.layerOrder = [.screen, .camera]

        let hit = PreviewStageEditing.layer(
            at: CGPoint(x: 0.5, y: 0.5),
            sceneLayout: layout,
            enabledSources: [.screen, .camera],
            frameForLayer: { layout.frame(for: $0) }
        )

        XCTAssertEqual(hit, .camera)
    }

    func testResizeAnchorIncludesEdgeHitAreas() {
        let frame = CGRect(x: 20, y: 30, width: 100, height: 80)

        XCTAssertEqual(
            PreviewStageEditing.resizeAnchor(at: CGPoint(x: 70, y: 110), in: frame),
            .top
        )
        XCTAssertEqual(
            PreviewStageEditing.resizeAnchor(at: CGPoint(x: 20, y: 30), in: frame),
            .bottomLeft
        )
    }

    func testCornerResizeAnchorExcludesEdgeHitAreas() {
        let frame = CGRect(x: 20, y: 30, width: 100, height: 80)

        XCTAssertNil(
            PreviewStageEditing.cornerResizeAnchor(at: CGPoint(x: 70, y: 110), in: frame)
        )
        XCTAssertEqual(
            PreviewStageEditing.cornerResizeAnchor(at: CGPoint(x: 20, y: 30), in: frame),
            .bottomLeft
        )
    }

    func testCropDragModesPreferResizeOverMove() {
        let cropFrame = CGRect(x: 20, y: 30, width: 100, height: 80)

        XCTAssertEqual(
            PreviewStageEditing.screenCropDragMode(at: CGPoint(x: 20, y: 30), cropFrame: cropFrame),
            .screenCropResize(.bottomLeft)
        )
        XCTAssertEqual(
            PreviewStageEditing.screenCropDragMode(at: CGPoint(x: 70, y: 70), cropFrame: cropFrame),
            .screenCropMove
        )
    }

    func testConstrainedScreenCropHandlesStayInsideSourceFrame() {
        let cropFrame = CGRect(x: 20, y: 30, width: 100, height: 80)
        let sourceFrame = cropFrame
        let handles = PreviewStageEditing.resizeHandles(for: cropFrame, constrainedTo: sourceFrame)

        XCTAssertEqual(handles[.topLeft]?.minX, sourceFrame.minX)
        XCTAssertEqual(handles[.topLeft]?.maxY, sourceFrame.maxY)
        XCTAssertEqual(handles[.topRight]?.maxX, sourceFrame.maxX)
        XCTAssertEqual(handles[.bottomLeft]?.minY, sourceFrame.minY)
    }

    func testScreenCropUsesConstrainedCornerHitAreaAtFullscreenEdge() {
        let cropFrame = CGRect(x: 20, y: 30, width: 100, height: 80)
        let sourceFrame = cropFrame

        XCTAssertEqual(
            PreviewStageEditing.screenCropDragMode(
                at: CGPoint(x: 24, y: 106),
                cropFrame: cropFrame,
                constrainedTo: sourceFrame
            ),
            .screenCropResize(.topLeft)
        )
    }
}
