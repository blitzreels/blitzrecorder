import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class PreviewStageViewTests: XCTestCase {
    func testChangingCaptureLayoutImmediatelyUpdatesRenderedCanvasAspectRatio() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.enabledSources = [.screen]

        view.captureLayout = .vertical
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.renderedCanvasAspectRatio, CaptureLayout.vertical.aspectRatio, accuracy: 0.01)

        view.captureLayout = .horizontal
        XCTAssertEqual(view.renderedCanvasAspectRatio, CaptureLayout.horizontal.aspectRatio, accuracy: 0.01)
    }

    func testCropFillUsesFullMediaFrameWhileSelectionMarqueeIsClampedToCanvas() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera

        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: -0.25, y: 0, width: 1.5, height: 1)
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        let selectionFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        let canvasFrame = view.renderedCanvasFrameForTesting
        let mediaFrame = view.renderedCameraFrameForTesting

        // The crop FILL layer (the camera media) uses the full rendered media
        // frame, which overscans the canvas horizontally for an off-canvas source.
        XCTAssertLessThan(mediaFrame.minX, canvasFrame.minX)
        XCTAssertGreaterThan(mediaFrame.width, canvasFrame.width)

        // The selection MARQUEE, however, is clamped to the visible canvas so the
        // green frame never spills into the side gaps (hit-testing still uses the
        // full, unclamped frame).
        XCTAssertGreaterThanOrEqual(selectionFrame.minX, canvasFrame.minX - 0.0001)
        XCTAssertLessThanOrEqual(selectionFrame.maxX, canvasFrame.maxX + 0.0001)
        XCTAssertLessThanOrEqual(selectionFrame.width, canvasFrame.width + 0.0001)
        XCTAssertEqual(selectionFrame.height, canvasFrame.height, accuracy: 0.0001)
    }

    func testCropToolbarTracksActiveCropSelection() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.camera]
        view.selectedLayer = .camera
        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.2)
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        view.beginCameraCropEditing()

        let selectionFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        let toolbarFrame = try XCTUnwrap(view.renderedCropToolbarFrameForTesting)
        XCTAssertEqual(toolbarFrame.midX, selectionFrame.midX, accuracy: 0.5)
        let isAboveSelection = toolbarFrame.minY > selectionFrame.maxY
        let isInsideSelectionTop = toolbarFrame.minY >= selectionFrame.minY && toolbarFrame.maxY <= selectionFrame.maxY
        XCTAssertTrue(isAboveSelection || isInsideSelectionTop)

        view.cancelCameraCropEditing()

        XCTAssertNil(view.renderedCropToolbarFrameForTesting)
    }

    func testFullscreenWebcamFillsPaddedCanvasWhenPaddingIsEnabled() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.canvasPadding = 0.12
        view.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let expectedFrame = SceneLayoutProjection.padded(
            view.renderedCanvasFrameForTesting,
            in: view.renderedCanvasFrameForTesting,
            padding: view.canvasPadding
        )
        XCTAssertRect(view.renderedCameraFrameForTesting, equals: expectedFrame)
    }

    func testLayerInteractionLockPreventsDraggingCanvasItems() {
        let view = PreviewStageView()
        let window = hostInWindow(view)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.sceneLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        view.layoutSubtreeIfNeeded()
        view.selectedLayer = .camera

        let originalLayout = view.sceneLayout
        var changeCount = 0
        view.onSceneLayoutChanged = { _ in
            changeCount += 1
        }
        view.allowsLayerInteraction = false

        let cameraFrame = view.renderedCameraFrameForTesting
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: CGPoint(x: cameraFrame.midX, y: cameraFrame.midY), in: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: CGPoint(x: cameraFrame.midX + 80, y: cameraFrame.midY + 80), in: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: CGPoint(x: cameraFrame.midX + 80, y: cameraFrame.midY + 80), in: window))

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(view.sceneLayout.cameraFrame, originalLayout.cameraFrame)
        XCTAssertNil(view.renderedSelectionFrameForTesting)
    }

    func testSingleVisibleScreenShowsSelectionOutlineWithoutResizeHandles() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .horizontal
        view.enabledSources = [.screen]
        view.selectedLayer = .screen
        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .horizontal)
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(view.renderedSelectionFrameForTesting)
        XCTAssertFalse(view.renderedSelectionShowsResizeHandlesForTesting)
    }

    func testScreenSelectionOverlayAppearsWhenCameraIsAlsoVisible() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .horizontal
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .screen
        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .horizontal)
        view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(try XCTUnwrap(view.renderedSelectionFrameForTesting))
        XCTAssertTrue(view.renderedSelectionShowsResizeHandlesForTesting)
    }

    func testCanSelectLayerFrameOutsideCanvas() {
        let view = PreviewStageView()
        let window = hostInWindow(view)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera

        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.88, width: 1, height: 0.3)
        layout.cameraFrame = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.5)
        layout.layerOrder = [.screen, .camera]
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        var selectedLayer: SceneLayerKind?
        view.onLayerSelected = { selectedLayer = $0 }

        let screenFrame = view.renderedScreenFrameForTesting
        let canvasFrame = view.renderedCanvasFrameForTesting
        XCTAssertGreaterThan(screenFrame.maxY, canvasFrame.maxY)

        let point = CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 8)
        XCTAssertFalse(canvasFrame.contains(point))
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window))

        XCTAssertEqual(selectedLayer, .screen)
        XCTAssertEqual(view.selectedLayer, .screen)
    }

    func testNormalLayerCornerResizePreservesAspectRatio() {
        let view = PreviewStageView()
        let window = hostInWindow(view)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera
        var layout = SceneLayout()
        layout.cameraFrame = CGRect(x: 0.2, y: 0.2, width: 0.38, height: 0.28)
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        let originalFrame = view.sceneLayout.cameraFrame
        let originalAspectRatio = originalFrame.width / originalFrame.height
        let cameraFrame = view.renderedCameraFrameForTesting
        let start = CGPoint(x: cameraFrame.maxX, y: cameraFrame.maxY)
        let end = CGPoint(x: cameraFrame.maxX + 70, y: cameraFrame.maxY + 20)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, in: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, in: window))

        let resizedFrame = view.sceneLayout.cameraFrame
        XCTAssertGreaterThan(resizedFrame.width, originalFrame.width)
        XCTAssertGreaterThan(resizedFrame.height, originalFrame.height)
        XCTAssertEqual(resizedFrame.width / resizedFrame.height, originalAspectRatio, accuracy: 0.0001)
    }

    func testLayerInteractionLockStillAllowsCameraCropEditing() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.camera]
        view.allowsLayerInteraction = false

        view.beginCameraCropEditing()

        XCTAssertTrue(view.isCameraCropEditingEnabled)
    }

    func testCameraCropInteractionLockPreventsCameraCropEditing() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.camera]
        view.allowsCameraCropInteraction = false

        view.beginCameraCropEditing()

        XCTAssertFalse(view.isCameraCropEditingEnabled)
    }

    func testCameraCropEditingShowsFullSourceAroundFullscreenWebcamCrop() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera
        view.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let normalCameraFrame = view.renderedCameraFrameForTesting
        view.beginCameraCropEditing()
        view.layoutSubtreeIfNeeded()

        let sourceFrame = view.renderedCameraFrameForTesting
        let selectionFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        XCTAssertEqual(sourceFrame.height, normalCameraFrame.height, accuracy: 0.0001)
        XCTAssertGreaterThan(sourceFrame.width, normalCameraFrame.width)
        XCTAssertRect(selectionFrame, equals: normalCameraFrame)
    }

    func testEndingCameraCropEditingRestoresFullscreenWebcamFrame() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera
        view.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let normalCameraFrame = view.renderedCameraFrameForTesting
        view.beginCameraCropEditing()
        view.cancelCameraCropEditing()

        XCTAssertRect(view.renderedCameraFrameForTesting, equals: normalCameraFrame)
    }

    func testCameraCropEditingMovesCropAcrossFullSourceFrame() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera
        view.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        view.beginCameraCropEditing()
        view.layoutSubtreeIfNeeded()

        view.updateCameraCropDraft(position: CGPoint(x: 1, y: 0))

        let sourceFrame = view.renderedCameraFrameForTesting
        let selectionFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        XCTAssertEqual(selectionFrame.maxX, sourceFrame.maxX, accuracy: 0.0001)
        XCTAssertEqual(selectionFrame.height, sourceFrame.height, accuracy: 0.0001)
    }

    func testCameraCropEditingUsesPartialCameraZoneAsCropTarget() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .camera
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        let normalCameraFrame = view.renderedCameraFrameForTesting
        view.beginCameraCropEditing()
        view.layoutSubtreeIfNeeded()

        let sourceFrame = view.renderedCameraFrameForTesting
        let selectionFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        XCTAssertEqual(selectionFrame.height, view.renderedCanvasFrameForTesting.height * 0.5, accuracy: 0.0001)
        XCTAssertRect(selectionFrame, equals: normalCameraFrame)
        XCTAssertGreaterThan(sourceFrame.width, selectionFrame.width)
    }

    func testFullscreenScreenFitsInsidePaddedCanvasWhenPaddingIsEnabled() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen]
        view.canvasPadding = 0.12
        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let expectedFrame = SceneLayoutProjection.padded(
            view.renderedCanvasFrameForTesting,
            in: view.renderedCanvasFrameForTesting,
            padding: view.canvasPadding
        )
        let fittedHeight = expectedFrame.width / SceneLayout.defaultScreenAspectRatio
        XCTAssertRect(
            view.renderedScreenFrameForTesting,
            equals: CGRect(
                x: expectedFrame.minX,
                y: expectedFrame.midY - fittedHeight / 2,
                width: expectedFrame.width,
                height: fittedHeight
            )
        )
    }

    func testExplicitScreenCropStillFillsPaddedCanvasWhenPaddingIsEnabled() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen]
        view.canvasPadding = 0.12
        view.screenCrop = CGRect(x: 0.34, y: 0, width: 0.32, height: 1)
        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let expectedFrame = SceneLayoutProjection.padded(
            view.renderedCanvasFrameForTesting,
            in: view.renderedCanvasFrameForTesting,
            padding: view.canvasPadding
        )
        XCTAssertRect(view.renderedScreenFrameForTesting, equals: expectedFrame)
    }

    func testPaddingRoundsScreenAndFullscreenWebcamPreviewCorners() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.canvasPadding = 0.12
        view.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(view.screenPreview.layer?.cornerRadius ?? 0, 0)
        XCTAssertGreaterThan(view.cameraPreview.layer?.cornerRadius ?? 0, 0)
        XCTAssertGreaterThan(view.screenPreview.layer?.borderWidth ?? 0, 0)
        XCTAssertGreaterThan(view.cameraPreview.layer?.borderWidth ?? 0, 0)
    }

    func testFullWidthStackedSectionsStaySquareWhenPaddingIsDisabled() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.canvasPadding = 0
        view.sceneLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.screenPreview.layer?.cornerRadius, 0)
        XCTAssertEqual(view.cameraPreview.layer?.cornerRadius, 0)
        XCTAssertEqual(view.screenPreview.layer?.borderWidth, 0)
        XCTAssertEqual(view.cameraPreview.layer?.borderWidth, 0)
    }

    func testSingleCameraPreviewMatchesPaddedRenderFrame() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.camera]
        view.canvasPadding = 0.12
        var layout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        layout.cameraFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        let expectedFrame = SceneLayoutProjection.padded(
            view.renderedCanvasFrameForTesting,
            in: view.renderedCanvasFrameForTesting,
            padding: view.canvasPadding
        )
        XCTAssertRect(view.renderedCameraFrameForTesting, equals: expectedFrame)
        XCTAssertGreaterThan(view.cameraPreview.layer?.borderWidth ?? 0, 0)
    }

    func testSwitchingToFullscreenScreenHidesCameraAndFillsCanvas() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.sceneLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        view.layoutSubtreeIfNeeded()

        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        view.enabledSources = [.screen]
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.cameraPreview.isHidden)
        XCTAssertFalse(view.screenPreview.isHidden)
        XCTAssertEqual(view.renderedScreenFrameForTesting.minX, view.renderedCanvasFrameForTesting.minX, accuracy: 0.0001)
        XCTAssertEqual(view.renderedScreenFrameForTesting.minY, view.renderedCanvasFrameForTesting.minY, accuracy: 0.0001)
        XCTAssertEqual(view.renderedScreenFrameForTesting.width, view.renderedCanvasFrameForTesting.width, accuracy: 0.0001)
        XCTAssertEqual(view.renderedScreenFrameForTesting.height, view.renderedCanvasFrameForTesting.height, accuracy: 0.0001)
    }

    func testScreenCropEditingFillsPortraitCanvasWithoutLetterboxBars() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen]
        view.screenSourceAspectRatio = 16.0 / 9.0
        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        view.beginScreenCropEditing(crop: nil)

        let canvasFrame = view.renderedCanvasFrameForTesting
        let screenFrame = view.renderedScreenFrameForTesting
        // The 16:9 display aspect-fills the portrait crop editor: full canvas
        // height, wider than the canvas, centered. No letterbox bars are shown
        // inside the crop zone.
        XCTAssertLessThan(screenFrame.minX, canvasFrame.minX)
        XCTAssertGreaterThan(screenFrame.maxX, canvasFrame.maxX)
        XCTAssertEqual(screenFrame.minY, canvasFrame.minY, accuracy: 0.5)
        XCTAssertEqual(screenFrame.maxY, canvasFrame.maxY, accuracy: 0.5)

        // The default crop selects the visible output slot, not the overscanned
        // off-canvas source margins.
        XCTAssertRect(try XCTUnwrap(view.renderedSelectionFrameForTesting), equals: canvasFrame)
    }

    func testScreenCropEditingCanResizeSourceInsidePortraitCanvas() throws {
        let view = PreviewStageView()
        let window = hostInWindow(view)
        view.captureLayout = .vertical
        view.enabledSources = [.screen]
        view.screenSourceAspectRatio = 16.0 / 9.0
        view.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)
        view.layoutSubtreeIfNeeded()

        view.beginScreenCropEditing(crop: nil)

        let initialFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        // The default crop fills the visible display, so crop inward by dragging
        // the right edge left; the selection must shrink and stay on-canvas. Grab
        // a few px inside the edge — the edge hit area excludes the exact maxX.
        let start = CGPoint(x: initialFrame.maxX - 4, y: initialFrame.midY)
        let end = CGPoint(x: initialFrame.maxX - 84, y: initialFrame.midY)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, in: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, in: window))

        let resizedFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        XCTAssertLessThan(resizedFrame.width, initialFrame.width)
    }

    func testStackedLayoutFitsPaddedScreenInsideCanvasWhenPaddingIsEnabled() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.canvasPadding = 0.12
        view.sceneLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let canvasFrame = view.renderedCanvasFrameForTesting
        let layout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        let expectedScreenFrame = SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(layout.screenFrame, in: canvasFrame, origin: .lowerLeft),
            in: canvasFrame,
            padding: view.canvasPadding
        )
        let expectedCameraFrame = SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(layout.cameraFrame, in: canvasFrame, origin: .lowerLeft),
            in: canvasFrame,
            padding: view.canvasPadding
        )
        XCTAssertRect(
            view.renderedScreenFrameForTesting,
            equals: aspectFit(sourceAspectRatio: SceneLayout.defaultScreenAspectRatio, in: expectedScreenFrame)
        )
        XCTAssertRect(view.renderedCameraFrameForTesting, equals: expectedCameraFrame)
    }

    func testScreenFocusScreenFitsPaddedCanvasWhenPaddingIsEnabled() {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.canvasPadding = 0.12
        view.sceneLayout = SceneLayout.presetLayout(.screenFocus, for: .vertical)
        view.layoutSubtreeIfNeeded()

        let canvasFrame = view.renderedCanvasFrameForTesting
        let layout = SceneLayout.presetLayout(.screenFocus, for: .vertical)
        let expectedScreenFrame = SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(layout.screenFrame, in: canvasFrame, origin: .lowerLeft),
            in: canvasFrame,
            padding: view.canvasPadding
        )
        XCTAssertRect(
            view.renderedScreenFrameForTesting,
            equals: aspectFit(sourceAspectRatio: SceneLayout.defaultScreenAspectRatio, in: expectedScreenFrame)
        )
    }
}

private func aspectFit(sourceAspectRatio: CGFloat, in rect: CGRect) -> CGRect {
    let targetAspectRatio = rect.width / rect.height
    if targetAspectRatio > sourceAspectRatio {
        let width = rect.height * sourceAspectRatio
        return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
    }
    let height = rect.width / sourceAspectRatio
    return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
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

@discardableResult
private func hostInWindow(_ view: NSView) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    view.frame = window.contentView?.bounds ?? window.frame
    return window
}

private func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
    )!
}
