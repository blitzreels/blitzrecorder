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
}
