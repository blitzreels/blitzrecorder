import AppKit
import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class PreviewStageEditingTests: XCTestCase {
    func testConstrainedFullScreenDragBeginsCropPanInFillMode() {
        XCTAssertTrue(PreviewStageEditing.shouldBeginConstrainedScreenCropPan(.init(
            layer: .screen,
            contentMode: .fill,
            startFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            proposedFrame: CGRect(x: 0.1, y: 0, width: 1, height: 1)
        )))
    }

    func testMovableScreenLayerDragRemainsLayerMove() {
        XCTAssertFalse(PreviewStageEditing.shouldBeginConstrainedScreenCropPan(.init(
            layer: .screen,
            contentMode: .fill,
            startFrame: CGRect(x: 0, y: 0, width: 0.6, height: 1),
            proposedFrame: CGRect(x: 0.1, y: 0, width: 0.6, height: 1)
        )))
    }

    func testConstrainedScreenDragDoesNotCropPanInFitMode() {
        XCTAssertFalse(PreviewStageEditing.shouldBeginConstrainedScreenCropPan(.init(
            layer: .screen,
            contentMode: .fit,
            startFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            proposedFrame: CGRect(x: 0.1, y: 0, width: 1, height: 1)
        )))
    }

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

    func testSingleVisibleScreenLayerCanBeEdited() {
        XCTAssertTrue(PreviewStageEditing.canEditLayerFrame(
            .screen,
            allowsLayerInteraction: true,
            enabledSources: [.screen],
            isCameraCropEditingEnabled: false,
            isScreenCropEditingEnabled: false
        ))
    }

    func testDisabledScreenLayerCannotBeEdited() {
        XCTAssertFalse(PreviewStageEditing.canEditLayerFrame(
            .screen,
            allowsLayerInteraction: true,
            enabledSources: [.camera],
            isCameraCropEditingEnabled: false,
            isScreenCropEditingEnabled: false
        ))
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

final class PreviewStageCropGeometryTests: XCTestCase {
    func testFittedSourceFrameCoversWideTarget() {
        let target = CGRect(x: 0, y: 0, width: 200, height: 100)
        let fitted = PreviewStageCropGeometry.fittedSourceFrame(target: target, sourceAspectRatio: 1)
        XCTAssertEqual(fitted.width, 200, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, 200, accuracy: 0.0001)
        XCTAssertEqual(fitted.midY, target.midY, accuracy: 0.0001)
    }

    func testNormalizedCropRoundTripsPixelFrame() {
        let source = CGRect(x: 10, y: 20, width: 100, height: 80)
        let pixel = CGRect(x: 20, y: 30, width: 50, height: 40)
        let normalized = PreviewStageCropGeometry.normalizedCrop(pixelFrame: pixel, in: source)
        let restored = PreviewStageCropGeometry.cropFrame(in: source, normalizedCrop: normalized)
        XCTAssertEqual(restored.minX, pixel.minX, accuracy: 0.0001)
        XCTAssertEqual(restored.minY, pixel.minY, accuracy: 0.0001)
        XCTAssertEqual(restored.width, pixel.width, accuracy: 0.0001)
        XCTAssertEqual(restored.height, pixel.height, accuracy: 0.0001)
    }

    func testClampedPixelFrameStaysInsideSource() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 100)
        let clamped = PreviewStageCropGeometry.clampedPixelFrame(
            CGRect(x: -20, y: 80, width: 200, height: 50),
            in: source
        )
        XCTAssertEqual(clamped.minX, 0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(clamped.minY, 0)
        XCTAssertLessThanOrEqual(clamped.maxX, 100)
        XCTAssertLessThanOrEqual(clamped.maxY, 100)
    }

    func testMouseDownPrefersScreenCropOverLayerHits() {
        XCTAssertEqual(
            PreviewStageEditing.mouseDownHit(.init(
                isScreenCropEditingEnabled: true,
                hasScreen: true,
                screenCropMode: .screenCropMove,
                allowsCameraCropInteraction: true,
                isCameraCropEditingEnabled: true,
                hasCamera: true,
                cameraCropMode: .cropMove,
                allowsLayerInteraction: true,
                resizeHit: (.camera, .topLeft),
                layerAtPoint: .camera,
                canvasContainsPoint: true
            )),
            .screenCrop(.screenCropMove)
        )
    }

    func testMouseDownIgnoresLayerHitsWhenInteractionIsDisabled() {
        XCTAssertEqual(
            PreviewStageEditing.mouseDownHit(.init(
                isScreenCropEditingEnabled: false,
                hasScreen: true,
                screenCropMode: nil,
                allowsCameraCropInteraction: false,
                isCameraCropEditingEnabled: false,
                hasCamera: true,
                cameraCropMode: nil,
                allowsLayerInteraction: false,
                resizeHit: (.camera, .topLeft),
                layerAtPoint: .camera,
                canvasContainsPoint: true
            )),
            .ignore
        )
    }

    func testMouseDownSelectsBackgroundInsideCanvas() {
        XCTAssertEqual(
            PreviewStageEditing.mouseDownHit(.init(
                isScreenCropEditingEnabled: false,
                hasScreen: true,
                screenCropMode: nil,
                allowsCameraCropInteraction: true,
                isCameraCropEditingEnabled: false,
                hasCamera: true,
                cameraCropMode: nil,
                allowsLayerInteraction: true,
                resizeHit: nil,
                layerAtPoint: nil,
                canvasContainsPoint: true
            )),
            .background
        )
    }

    func testDragTickConvertsConstrainedFillMoveIntoScreenCropPan() {
        XCTAssertFalse(PreviewStageDrag.allowsInteraction(
            kind: .move,
            isScreenCropEditingEnabled: true,
            allowsCameraCropInteraction: true,
            allowsLayerInteraction: false
        ))
        XCTAssertEqual(
            PreviewStageDrag.tick(.init(
                kind: .move,
                layer: .screen,
                startFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
                delta: CGPoint(x: 0.1, y: 0),
                screenContentMode: .fill
            )),
            .beginScreenCropPan(CGRect(x: 0.1, y: 0, width: 1, height: 1))
        )
        XCTAssertEqual(
            PreviewStageDrag.canvasDelta(
                from: CGPoint(x: 10, y: 10),
                to: CGPoint(x: 30, y: 50),
                canvasSize: CGSize(width: 100, height: 200)
            ),
            CGPoint(x: 0.2, y: 0.2)
        )
    }

    func testMouseDownBeginSelectsLayerWithoutDragWhenLocked() {
        XCTAssertEqual(
            PreviewStageDrag.begin(.init(
                hit: .layer(.camera),
                location: .zero,
                selectedLayer: .screen,
                canEditLayer: false,
                canBeginScreenCropPan: false,
                screenCropFrame: .zero,
                cameraNormalizedFrame: .zero,
                layerSelectionFrame: .zero,
                layerNormalizedSelection: .zero,
                layerNormalizedFrame: .zero,
                cameraCropAmount: .zero,
                cameraCropPosition: .zero,
                activeCameraCropAmount: .zero,
                activeCameraCropPosition: .zero
            )),
            .select(.camera, drag: nil, cursor: .none)
        )
        XCTAssertEqual(
            PreviewStageDrag.begin(.init(
                hit: .background,
                location: .zero,
                selectedLayer: .camera,
                canEditLayer: true,
                canBeginScreenCropPan: false,
                screenCropFrame: .zero,
                cameraNormalizedFrame: .zero,
                layerSelectionFrame: .zero,
                layerNormalizedSelection: .zero,
                layerNormalizedFrame: .zero,
                cameraCropAmount: .zero,
                cameraCropPosition: .zero,
                activeCameraCropAmount: .zero,
                activeCameraCropPosition: .zero
            )),
            .background
        )
    }

    func testDragCursorUsesClosedHandWhileMoving() {
        XCTAssertTrue(PreviewStageDrag.dragCursor(for: .move) === NSCursor.closedHand)
        XCTAssertTrue(PreviewStageDrag.dragCursor(for: .cropMove) === NSCursor.closedHand)
        XCTAssertTrue(
            PreviewStageDrag.dragCursor(for: .resize(.left)) === NSCursor.resizeLeftRight
        )
    }

    func testCropSessionCommitRequiresEditing() {
        XCTAssertNil(PreviewStageCropSession.committedCameraCrop(
            isEditing: false,
            amount: CGPoint(x: 0.2, y: 0.1),
            position: CGPoint(x: 0.4, y: 0.5)
        ))
        let camera = PreviewStageCropSession.committedCameraCrop(
            isEditing: true,
            amount: CGPoint(x: 0.2, y: 0.1),
            position: CGPoint(x: 0.4, y: 0.5)
        )
        XCTAssertEqual(camera?.0, CGPoint(x: 0.2, y: 0.1))
        XCTAssertEqual(camera?.1, CGPoint(x: 0.4, y: 0.5))
        XCTAssertNil(PreviewStageCropSession.committedScreenCrop(isEditing: false, draft: nil))
        XCTAssertEqual(
            PreviewStageCropSession.committedScreenCrop(isEditing: true, draft: nil),
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
    }
}
