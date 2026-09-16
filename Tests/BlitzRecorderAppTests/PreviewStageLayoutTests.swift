import AppKit
import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class PreviewStageLayoutTests: XCTestCase {
    func testFittedCanvasMatchesSceneSlotGeometry() {
        let rect = CGRect(x: 10, y: 20, width: 800, height: 400)
        XCTAssertEqual(
            PreviewStageLayout.fittedCanvas(in: rect, captureLayout: .vertical),
            SceneSlotGeometry.canvasFrame(in: rect, captureLayout: .vertical)
        )
        XCTAssertEqual(
            PreviewStageLayout.fittedCanvas(in: rect, captureLayout: .horizontal),
            SceneSlotGeometry.canvasFrame(in: rect, captureLayout: .horizontal)
        )
    }

    func testSelectionModeAndCropToolbarPlacement() {
        XCTAssertEqual(
            PreviewStageSelection.mode(.init(
                isBackgroundLayerSelected: true,
                isScreenCropEditingEnabled: false,
                hasScreen: true,
                canvasIsEmpty: false,
                allowsLayerInteraction: true,
                allowsCameraCropInteraction: true,
                isCameraCropEditingEnabled: false,
                selectedLayer: .camera,
                hasSelectedSource: true
            )),
            .background
        )
        XCTAssertEqual(
            PreviewStageSelection.mode(.init(
                isBackgroundLayerSelected: false,
                isScreenCropEditingEnabled: true,
                hasScreen: false,
                canvasIsEmpty: false,
                allowsLayerInteraction: true,
                allowsCameraCropInteraction: true,
                isCameraCropEditingEnabled: false,
                selectedLayer: .screen,
                hasSelectedSource: false
            )),
            .pendingScreenCrop
        )
        XCTAssertEqual(
            PreviewStageSelection.mode(.init(
                isBackgroundLayerSelected: false,
                isScreenCropEditingEnabled: false,
                hasScreen: true,
                canvasIsEmpty: false,
                allowsLayerInteraction: true,
                allowsCameraCropInteraction: true,
                isCameraCropEditingEnabled: true,
                selectedLayer: .camera,
                hasSelectedSource: true
            )),
            .cameraCrop
        )
        let toolbar = PreviewStageSelection.cropToolbarFrame(
            above: CGRect(x: 100, y: 100, width: 200, height: 80),
            in: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        XCTAssertEqual(toolbar.width, 206)
        XCTAssertEqual(toolbar.height, 40)
        XCTAssertEqual(toolbar.minX, 97)
        XCTAssertEqual(toolbar.minY, 188)
    }

    func testCameraPreviewCornerRadiusSkipsFullscreen() {
        XCTAssertEqual(PreviewStageLayout.sourceCornerRadius(for: .zero), 0)
        XCTAssertEqual(
            PreviewStageLayout.cameraPreviewCornerRadius(
                bounds: CGRect(x: 0, y: 0, width: 200, height: 200),
                isFullscreen: true,
                isFullWidth: false
            ),
            0
        )
        XCTAssertGreaterThan(
            PreviewStageLayout.cameraPreviewCornerRadius(
                bounds: CGRect(x: 0, y: 0, width: 200, height: 200),
                isFullscreen: false,
                isFullWidth: false
            ),
            0
        )

        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let canvas = CGRect(x: 40, y: 20, width: 320, height: 180)
        let crop = CGRect(x: 80, y: 40, width: 120, height: 80)
        let layerAppearance = PreviewStageSelection.appearance(.init(
            mode: .layer,
            bounds: bounds,
            canvasFrame: canvas,
            screenSourceFrame: .zero,
            screenCropFrame: .zero,
            cameraSourceFrame: .zero,
            cameraCropFrame: .zero,
            layerFrame: crop,
            showsLayerResizeHandles: true
        ))
        XCTAssertFalse(layerAppearance.isCropMode)
        XCTAssertEqual(layerAppearance.selectionFrame, crop)
        XCTAssertEqual(layerAppearance.overlayFrame, bounds)
        XCTAssertNil(layerAppearance.cropToolbarFrame)

        let screenCropAppearance = PreviewStageSelection.appearance(.init(
            mode: .screenCrop,
            bounds: bounds,
            canvasFrame: canvas,
            screenSourceFrame: canvas,
            screenCropFrame: crop,
            cameraSourceFrame: .zero,
            cameraCropFrame: .zero,
            layerFrame: .zero,
            showsLayerResizeHandles: false
        ))
        XCTAssertTrue(screenCropAppearance.isCropMode)
        XCTAssertEqual(screenCropAppearance.sourceFrame, canvas)
        XCTAssertEqual(
            screenCropAppearance.cropToolbarFrame,
            PreviewStageSelection.cropToolbarFrame(above: crop, in: bounds)
        )
    }
}

final class ScreenWindowFitTests: XCTestCase {
    func testApplicationMatchUsesBundleAndName() {
        let app = NSRunningApplication.current
        let matching = ScreenSourceBinding(
            kind: .application,
            displayID: nil,
            bundleIdentifier: app.bundleIdentifier,
            applicationName: app.localizedName,
            processID: app.processIdentifier,
            windowID: nil,
            windowTitle: nil
        )
        XCTAssertTrue(ScreenWindowFit.applicationMatches(app, binding: matching))

        var wrongBundle = matching
        wrongBundle.bundleIdentifier = "com.example.other"
        XCTAssertFalse(ScreenWindowFit.applicationMatches(app, binding: wrongBundle))

        var wrongName = matching
        wrongName.applicationName = "Not This App"
        XCTAssertFalse(ScreenWindowFit.applicationMatches(app, binding: wrongName))
    }
}
