import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class ScenePresetLayoutTests: XCTestCase {
    func testVerticalStackedUsesEqualScreenAndCameraHalves() {
        let layout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)

        XCTAssertRect(
            layout.screenFrame,
            equals: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        )
        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        )
    }

    func testWebcamFullscreenFitsLandscapeCameraInVerticalCanvasWithoutCrop() {
        let layout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)

        XCTAssertRect(
            layout.cameraFrame,
            equals: CGRect(x: 0, y: 0.341796875, width: 1, height: 0.31640625)
        )
        XCTAssertEqual(layout.layerOrder, [.screen, .camera])
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
