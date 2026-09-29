import AppKit
import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class PreviewStageLayoutTests: XCTestCase {
    func testTurningOffScreenFillsCanvasWithCameraInPreviewAndSavedScene() throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        settings.canvasBackgroundStyle = .macOSSonomaHorizon
        let canvas = CGRect(x: 0, y: 0, width: 900, height: 500)
        let preview = PreviewStageLayout.geometry(.init(
            canvas: canvas,
            enabledSources: settings.visibleSources,
            fillsCanvasWhenOnlyVideoSource: true,
            sceneLayout: settings.sceneLayout,
            screenFillsSceneFrame: false,
            screenCrop: nil,
            screenSourceAspectRatio: 16.0 / 9.0,
            cameraCropAmount: .zero,
            cameraCropPosition: .zero,
            canvasBackgroundStyle: settings.canvasBackgroundStyle,
            canvasPadding: 0,
            screenContentMode: .fill,
            cameraContentMode: .fill,
            cameraFramePadding: 0,
            cameraShadowEnabled: false
        ))
        XCTAssertEqual(preview.activeLayerOrder, [.camera])
        XCTAssertEqual(preview.targetRect(for: .camera), canvas)

        let stage = PreviewStageView()
        stage.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        stage.captureLayout = .horizontal
        stage.enabledSources = settings.visibleSources
        stage.fillsCanvasWhenOnlyVideoSource = true
        stage.sceneLayout = settings.sceneLayout
        stage.layoutSubtreeIfNeeded()
        XCTAssertEqual(stage.renderedCameraFrameForTesting, stage.renderedCanvasFrameForTesting)

        let scene = RecordingScene(settings: settings)
        let snapshot = RecordingProject.SceneSnapshot(scene)
        let restored = try XCTUnwrap(RecordingScene(snapshot: JSONDecoder().decode(
            RecordingProject.SceneSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )))
        let output = SceneRenderGeometry(canvas: canvas, scene: restored, origin: .lowerLeft)
        XCTAssertEqual(output.activeLayerOrder, [.camera])
        XCTAssertEqual(output.targetRect(for: .camera), canvas)
    }

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
        XCTAssertEqual(SceneLayoutProjection.cameraCornerRadius(for: .zero), 0)
        XCTAssertEqual(
            PreviewStageLayout.cameraPreviewCornerRadius(.init(
                isCamera: true,
                rect: CGRect(x: 0, y: 0, width: 200, height: 200),
                isFullscreen: true,
                isFullWidth: false,
                isCircle: false
            )),
            0
        )
        XCTAssertGreaterThan(
            PreviewStageLayout.cameraPreviewCornerRadius(.init(
                isCamera: true,
                rect: CGRect(x: 0, y: 0, width: 200, height: 200),
                isFullscreen: false,
                isFullWidth: false,
                isCircle: false
            )),
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
