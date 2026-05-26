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

    func testSelectionUsesVisibleCanvasFrameForCropFillLayer() throws {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .vertical
        view.enabledSources = [.camera]
        view.selectedLayer = .camera

        var layout = SceneLayout()
        layout.cameraFrame = SceneLayout.canvasFillingFrame(
            sourceAspectRatio: SceneLayout.cameraAspectRatio,
            canvasAspectRatio: CaptureLayout.vertical.aspectRatio
        )
        view.sceneLayout = layout
        view.layoutSubtreeIfNeeded()

        let selectionFrame = try XCTUnwrap(view.renderedSelectionFrameForTesting)
        let canvasFrame = view.renderedCanvasFrameForTesting
        XCTAssertEqual(selectionFrame.minX, canvasFrame.minX, accuracy: 0.0001)
        XCTAssertEqual(selectionFrame.minY, canvasFrame.minY, accuracy: 0.0001)
        XCTAssertEqual(selectionFrame.width, canvasFrame.width, accuracy: 0.0001)
        XCTAssertEqual(selectionFrame.height, canvasFrame.height, accuracy: 0.0001)
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

    func testScreenTopEdgeResizeChangesHeightWithoutChangingWidth() {
        let view = PreviewStageView()
        let window = hostInWindow(view)
        view.captureLayout = .vertical
        view.enabledSources = [.screen, .camera]
        view.selectedLayer = .screen
        view.sceneLayout = SceneLayout.screenSplitLayout(screenHeight: 0.5)
        view.layoutSubtreeIfNeeded()

        let screenFrame = view.renderedScreenFrameForTesting
        let start = CGPoint(x: screenFrame.midX, y: screenFrame.maxY)
        let end = CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 60)
        view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: window))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: end, in: window))
        view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, in: window))

        XCTAssertEqual(view.sceneLayout.screenFrame.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(view.sceneLayout.screenFrame.width, 1, accuracy: 0.0001)
        XCTAssertLessThan(view.sceneLayout.screenFrame.height, 0.5)
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

    func testFullscreenScreenFillsPaddedCanvasWhenPaddingIsEnabled() {
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

    func testStackedLayoutFitsPaddedCanvasWidthWhenPaddingIsEnabled() {
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
        XCTAssertRect(view.renderedScreenFrameForTesting, equals: expectedScreenFrame)
        XCTAssertRect(view.renderedCameraFrameForTesting, equals: expectedCameraFrame)
    }

    func testScreenFocusScreenFillsPaddedCanvasWhenPaddingIsEnabled() {
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
        XCTAssertRect(view.renderedScreenFrameForTesting, equals: expectedScreenFrame)
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
