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

    func testWebcamLeftUsesLeftThirdAndScreenRightTwoThirdsInHorizontalCanvas() {
        let layout = SceneLayout.presetLayout(.webcamLeft, for: .horizontal)

        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1))
        XCTAssertRect(layout.screenFrame, equals: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1))
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
    }

    func testWebcamLeftIsLandscapeOnly() {
        XCTAssertFalse(ScenePreset.webcamLeft.supports(.vertical))
        XCTAssertTrue(ScenePreset.webcamLeft.supports(.horizontal))
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
