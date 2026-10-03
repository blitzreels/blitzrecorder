import AppKit
import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class ScenePresetLayoutTests: XCTestCase {
    func testVerticalStackedFitsScreenFullWidthAtNativeAspect() {
        let layout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)

        XCTAssertRect(
            layout.screenFrame,
            equals: CGRect(x: 0, y: 0.68359375, width: 1, height: 0.31640625)
        )
        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0, y: 0, width: 1, height: 0.68359375)
        )
    }

    func testVerticalScreenFocusUsesStackedCameraShapeInBottomRight() {
        let layout = SceneLayout.presetLayout(.screenFocus, for: .vertical)

        XCTAssertEqual(layout.cameraFrame.maxX, 0.955, accuracy: 0.0001)
        XCTAssertEqual(layout.cameraFrame.minY, 0.045, accuracy: 0.0001)
        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0.455, y: 0.045, width: 0.5, height: 0.25)
        )
    }

    func testVerticalScreenTop50UsesEqualScreenAndCameraStrips() {
        let layout = SceneLayout.presetLayout(.screenTop50, for: .vertical)

        XCTAssertRect(layout.screenFrame, equals: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
        XCTAssertNotNil(layout.screenSplitHeight)
        XCTAssertEqual(layout.screenSplitHeight ?? 0, 0.5, accuracy: 0.0001)
    }

    func testScreenSplitLayoutFitsScreenToSelectedHeight() {
        let layout = SceneLayout.screenSplitLayout(screenHeight: 0.64, screenAspectRatio: 16.0 / 9.0)

        XCTAssertEqual(layout.screenFrame.height, 0.64, accuracy: 0.0001)
        XCTAssertEqual(layout.screenFrame.width, 1, accuracy: 0.0001)
        XCTAssertEqual(layout.screenFrame.midX, 0.5, accuracy: 0.0001)
        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 0.36))
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
        XCTAssertNotNil(layout.screenSplitHeight)
        XCTAssertEqual(layout.screenSplitHeight ?? 0, 0.64, accuracy: 0.0001)
    }

    func testScreenSplitLayoutKeepsScreenFullWidthWhenSelectedHeightIsShort() {
        let layout = SceneLayout.screenSplitLayout(screenHeight: 0.3, screenAspectRatio: 16.0 / 9.0)

        XCTAssertEqual(layout.screenFrame.height, 0.3, accuracy: 0.0001)
        XCTAssertEqual(layout.screenFrame.width, 1, accuracy: 0.0001)
        XCTAssertEqual(layout.screenFrame.midX, 0.5, accuracy: 0.0001)
        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 0.7))
    }

    func testLegacyAndFocusPresetsAreNoLongerShown() {
        XCTAssertFalse(ScenePreset.allCases.contains(.stackedHalves))
        XCTAssertFalse(ScenePreset.allCases.contains(.screenFocus))
        XCTAssertFalse(ScenePreset.allCases.contains(.screenTop70))
        XCTAssertFalse(ScenePreset.allCases.contains(.cameraFocus))
    }

    func testWebcamFullscreenUsesFullVerticalCanvasForCameraCrop() {
        let layout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)

        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
    }

    func testScreenFullscreenUsesFullVerticalCanvasForScreen() {
        let layout = SceneLayout.presetLayout(.screenFullscreen, for: .vertical)

        XCTAssertRect(
            layout.screenFrame,
            equals: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        XCTAssertEqual(layout.layerOrder, [.camera, .screen])
    }

    func testWebcamFullscreenUsesPortraitCameraSettingsAsFullVerticalCanvas() {
        let layout = SceneLayout.presetLayout(
            .webcamFullscreen,
            for: .vertical,
            cameraAspectRatio: 9.0 / 16.0
        )

        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
    }

    func testWebcamFullscreenFillsHorizontalCanvasExactly() {
        let layout = SceneLayout.presetLayout(.webcamFullscreen, for: .horizontal)

        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
    }

    func testScreenFullscreenFillsHorizontalCanvasExactly() {
        let layout = SceneLayout.presetLayout(.screenFullscreen, for: .horizontal)

        XCTAssertRect(layout.screenFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(layout.layerOrder, [.camera, .screen])
    }

    func testWebcamLeftUsesPortraitCameraColumnInHorizontalCanvas() {
        let layout = SceneLayout.presetLayout(.webcamLeft, for: .horizontal)
        let width: CGFloat = 81.0 / 256.0

        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: width, height: 1))
        XCTAssertRect(layout.screenFrame, equals: CGRect(x: width, y: 0, width: 1 - width, height: 1))
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
    }

    func testWebcamLeftIsLandscapeOnly() {
        XCTAssertFalse(ScenePreset.webcamLeft.supports(.vertical))
        XCTAssertTrue(ScenePreset.webcamLeft.supports(.horizontal))
    }

    func testCameraInsetDefaultsToBottomRightWideFrame() {
        let layout = SceneLayout.presetLayout(.cameraInset, for: .horizontal)

        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0.685, y: 0.035, width: 0.28, height: 0.28)
        )
        XCTAssertEqual(SceneLayout.cameraInsetAlignment(for: layout.cameraFrame), .bottomRight)
        XCTAssertEqual(SceneLayout.cameraInsetShape(for: layout.cameraFrame, in: .horizontal), .landscape)
        XCTAssertEqual(SceneLayout.cameraInsetSize(for: layout.cameraFrame, in: .horizontal), 0.28, accuracy: 0.0001)
    }

    func testVerticalCameraInsetDefaultsToFullWidthLowerBand() {
        let layout = SceneLayout.presetLayout(.cameraInset, for: .vertical)

        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0.035, y: 0.035, width: 0.93, height: 0.2942578125)
        )
        XCTAssertEqual(SceneLayout.cameraInsetAlignment(for: layout.cameraFrame), .bottomRight)
        XCTAssertEqual(SceneLayout.cameraInsetShape(for: layout.cameraFrame, in: .vertical), .landscape)
        XCTAssertEqual(SceneLayout.cameraInsetSize(for: layout.cameraFrame, in: .vertical), 0.93, accuracy: 0.0001)
        XCTAssertEqual(SceneLayout.maximumCameraInsetSize(for: .vertical), 0.93, accuracy: 0.0001)
    }

    func testCameraInsetIsAvailableInBothCanvasOrientations() {
        XCTAssertTrue(ScenePreset.cameraInset.supports(.vertical))
        XCTAssertTrue(ScenePreset.cameraInset.supports(.horizontal))
    }

    func testCameraInsetCanUseBottomLeftPortraitFrame() {
        let frame = SceneLayout.cameraInsetFrame(
            for: .horizontal,
            alignment: .bottomLeft,
            shape: .portrait,
            size: 0.42
        )

        XCTAssertEqual(frame.minX, 0.035, accuracy: 0.0001)
        XCTAssertEqual(frame.minY, 0.035, accuracy: 0.0001)
        XCTAssertEqual(frame.height, 0.42, accuracy: 0.0001)
        XCTAssertEqual((frame.width / frame.height) * CaptureLayout.horizontal.aspectRatio, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(SceneLayout.cameraInsetAlignment(for: frame), .bottomLeft)
        XCTAssertEqual(SceneLayout.cameraInsetShape(for: frame, in: .horizontal), .portrait)
        XCTAssertEqual(SceneLayout.cameraInsetSize(for: frame, in: .horizontal), 0.42, accuracy: 0.0001)
    }

    func testCameraInsetFrameUsesRealCameraAspectRatio() {
        let frame = SceneLayout.cameraInsetFrame(
            for: .horizontal,
            alignment: .bottomRight,
            shape: .landscape,
            size: 0.28,
            sourceAspectRatio: 4.0 / 3.0
        )

        XCTAssertEqual(
            (frame.width / frame.height) * CaptureLayout.horizontal.aspectRatio,
            4.0 / 3.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(SceneLayout.cameraInsetShape(for: frame, in: .horizontal), .landscape)
    }

    func testVerticalCameraInsetFrameUsesInvertedRealAspectRatio() {
        let frame = SceneLayout.cameraInsetFrame(
            for: .horizontal,
            alignment: .bottomLeft,
            shape: .portrait,
            size: 0.42,
            sourceAspectRatio: 4.0 / 3.0
        )

        XCTAssertEqual(
            (frame.width / frame.height) * CaptureLayout.horizontal.aspectRatio,
            3.0 / 4.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(SceneLayout.cameraInsetShape(for: frame, in: .horizontal), .portrait)
    }

    func testCircleCameraInsetRendersSquareTargetWithHalfSideRadius() throws {
        for layout in CaptureLayout.allCases {
            for padding in [CGFloat(0), 0.06] {
                var settings = RecordingSettings()
                settings.layout = layout
                settings.canvasPadding = padding
                settings = RecordingSceneMutation.applyingCameraInset(
                    alignment: .bottomRight,
                    shape: .circle,
                    size: 0.3,
                    to: settings,
                    screenAspectRatio: 16.0 / 9.0,
                    cameraAspectRatio: 16.0 / 9.0
                ).settings
                let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
                let policy = SceneRenderPlacementPolicy(
                    canvas: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height),
                    scene: RecordingScene(settings: settings),
                    origin: .lowerLeft
                )
                let camera = try XCTUnwrap(policy.activePlacements.first { $0.kind == .camera })

                XCTAssertEqual(settings.sceneLayout.cameraMask, .circle)
                XCTAssertEqual(settings.sceneLayout.cameraInsetShape(in: layout), .circle)
                XCTAssertEqual(settings.sceneLayout.cameraInsetSize(in: layout), 0.3, accuracy: 0.0001)
                XCTAssertTrue(SceneLayout.isCameraInsetFrame(settings.sceneLayout.cameraFrame))
                XCTAssertTrue(policy.rendersCircularCamera)
                XCTAssertEqual(camera.targetRect.width, camera.targetRect.height, accuracy: 1)
                XCTAssertEqual(
                    camera.cornerRadius,
                    min(camera.targetRect.width, camera.targetRect.height) / 2,
                    accuracy: 0.0001
                )
                XCTAssertEqual(policy.cornerRadius(for: .camera), camera.cornerRadius, accuracy: 0.0001)
            }
        }
    }

    @MainActor
    func testRectangleInsetCameraCornersMatchThePreview() throws {
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.sceneLayout.cameraMask = .circle
        settings = RecordingSceneMutation.applyingCameraInset(
            alignment: .bottomLeft,
            shape: .landscape,
            size: 0.3,
            to: settings,
            screenAspectRatio: 16.0 / 9.0,
            cameraAspectRatio: 16.0 / 9.0
        ).settings
        let policy = SceneRenderPlacementPolicy(
            canvas: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scene: RecordingScene(settings: settings),
            origin: .lowerLeft
        )

        XCTAssertEqual(settings.sceneLayout.cameraMask, .rectangle)
        XCTAssertEqual(settings.sceneLayout.cameraInsetShape(in: .horizontal), .landscape)
        let target = policy.targetRect(for: .camera)
        XCTAssertEqual(policy.cornerRadius(for: .camera), SceneLayoutProjection.cameraCornerRadius(for: target))
        XCTAssertGreaterThan(policy.cornerRadius(for: .camera), 0)

        let preview = PreviewStageView()
        preview.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        preview.captureLayout = .horizontal
        preview.enabledSources = [.screen, .camera]
        preview.sceneLayout = settings.sceneLayout
        preview.layoutSubtreeIfNeeded()
        let previewFrame = preview.renderedCameraFrameForTesting
        let previewRadius = try XCTUnwrap(preview.cameraPreview.layer?.cornerRadius)
        XCTAssertEqual(
            previewRadius / min(previewFrame.width, previewFrame.height),
            policy.cornerRadius(for: .camera) / min(target.width, target.height),
            accuracy: 0.0001
        )
    }

    func testCircleMaskIsDroppedWhenCameraFillsTheCanvas() {
        var layout = SceneLayout.presetLayout(.webcamFullscreen, for: .horizontal)
        layout.cameraMask = .circle
        let policy = SceneRenderPlacementPolicy(
            canvas: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scene: RecordingScene(enabledSources: [.camera], sceneLayout: layout, fillsCanvasWhenOnlyVideoSource: true),
            origin: .lowerLeft
        )

        XCTAssertFalse(policy.rendersCircularCamera)
        XCTAssertEqual(policy.cornerRadius(for: .camera), 0)
    }

    func testApplyingPresetClearsCircleMask() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.sceneLayout.cameraMask = .circle
        let next = RecordingSceneMutation.applyingPreset(
            .stackedHalves,
            to: settings,
            screenAspectRatio: 16.0 / 9.0,
            cameraAspectRatio: 16.0 / 9.0
        )

        XCTAssertEqual(next.sceneLayout.cameraMask, .rectangle)
    }

    func testCameraFocusIsNoLongerSupported() {
        XCTAssertFalse(ScenePreset.cameraFocus.supports(.vertical))
        XCTAssertFalse(ScenePreset.cameraFocus.supports(.horizontal))
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

final class AdditionalScenePresetTests: XCTestCase {
    func testCameraRightMirrorsCameraLeftWithoutGapsOrOverlap() {
        for canvas in [CaptureLayout.horizontal, .square] {
            let left = SceneLayout.presetLayout(.webcamLeft, for: canvas)
            let right = SceneLayout.presetLayout(.cameraRight, for: canvas)
            XCTAssertEqual(right.cameraFrame.width, left.cameraFrame.width)
            XCTAssertEqual(right.screenFrame.width, left.screenFrame.width)
            XCTAssertEqual(right.cameraFrame.maxX, 1, accuracy: 0.0001)
            XCTAssertEqual(right.screenFrame.minX, 0)
            XCTAssertEqual(right.screenFrame.maxX, right.cameraFrame.minX)
            XCTAssertEqual(right.cameraFrame.height, 1)
            XCTAssertEqual(right.screenFrame.height, 1)
            XCTAssertEqual(right.layerOrder, left.layerOrder)
        }
        XCTAssertFalse(ScenePreset.cameraRight.supports(.vertical))
    }

    func testEqualSplitGivesEachSourceHalfTheCanvas() {
        for canvas in [CaptureLayout.horizontal, .square] {
            let layout = SceneLayout.presetLayout(.equalSplit, for: canvas)
            XCTAssertEqual(layout.cameraFrame, CGRect(x: 0, y: 0, width: 0.5, height: 1))
            XCTAssertEqual(layout.screenFrame, CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
            XCTAssertNil(layout.screenSplitHeight)
        }
        XCTAssertFalse(ScenePreset.equalSplit.supports(.vertical))
    }

    func testScreenInsetKeepsWholeScreenAboveFullCanvasCameraForEveryAspectRatio() {
        for canvas in CaptureLayout.allCases {
            for screenRatio: CGFloat in [16.0 / 9.0, 4.0 / 3.0, 9.0 / 16.0] {
                for cameraRatio: CGFloat in [16.0 / 9.0, 9.0 / 16.0] {
                    let layout = SceneLayout.presetLayout(
                        .screenInset,
                        for: canvas,
                        screenAspectRatio: screenRatio,
                        cameraAspectRatio: cameraRatio
                    )
                    XCTAssertEqual(layout.cameraFrame, CGRect(x: 0, y: 0, width: 1, height: 1))
                    XCTAssertTrue(layout.cameraFrame.contains(layout.screenFrame))
                    XCTAssertGreaterThan(layout.screenFrame.minY, 0.5)
                    XCTAssertLessThan(layout.screenFrame.width * layout.screenFrame.height, 0.25)
                    XCTAssertEqual(
                        layout.screenFrame.width * canvas.aspectRatio / layout.screenFrame.height,
                        screenRatio,
                        accuracy: 0.0001
                    )
                    XCTAssertEqual(layout.layerOrder, [.camera, .screen])
                    XCTAssertTrue(ScenePreset.screenInset.supports(canvas))
                }
            }
        }
    }

    func testNewPresetsRestoreBothSourcesAndSurviveSettingsReload() throws {
        let suite = "AdditionalScenePresetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for preset in [ScenePreset.cameraRight, .equalSplit, .screenInset] {
            for canvas in CaptureLayout.allCases where preset.supports(canvas) {
                var settings = RecordingSettings()
                settings.layout = canvas
                settings.enabledSources = [.camera, .microphone]
                settings.hiddenSources = [.screen, .camera]
                let applied = RecordingSceneMutation.applyingPreset(
                    preset,
                    to: settings,
                    screenAspectRatio: 16.0 / 9.0,
                    cameraAspectRatio: 16.0 / 9.0
                )
                XCTAssertTrue(applied.visibleSources.isSuperset(of: [.screen, .camera]))
                XCTAssertTrue(applied.enabledSources.contains(.microphone))
                RecordingSettingsStore.save(applied, defaults: defaults)
                let reloaded = RecordingSettingsStore.load(defaults: defaults)
                XCTAssertEqual(reloaded.selectedScenePreset, preset)
                XCTAssertEqual(reloaded.sceneLayout, applied.sceneLayout)
            }
        }
    }
}
