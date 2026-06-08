import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class ScreenCaptureGeometryTests: XCTestCase {
    func testSceneLayoutDoesNotOverrideScreenSourceAspectRatio() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.selectedScenePreset = .stackedHalves
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let aspectRatio = ScreenCaptureGeometry.screenSourceAspectRatio(
            for: settings,
            fallback: 16.0 / 9.0
        )

        XCTAssertEqual(aspectRatio, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testExplicitScreenCropControlsScreenSourceAspectRatio() {
        var settings = RecordingSettings()
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)

        let aspectRatio = ScreenCaptureGeometry.screenSourceAspectRatio(
            for: settings,
            fallback: 16.0 / 9.0
        )

        XCTAssertEqual(aspectRatio, 2.0, accuracy: 0.0001)
    }

    func testScreenSourceGeometryOwnsCropProjection() {
        let geometry = ScreenSourceGeometry(
            usesPickedContent: false,
            selectedDisplayID: "42",
            normalizedCrop: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.4),
            sourceAspectRatio: nil
        )

        XCTAssertEqual(geometry.aspectRatio(), 1.25, accuracy: 0.0001)
        XCTAssertEqual(
            geometry.sourceRect(in: CGRect(x: 10, y: 20, width: 200, height: 100)),
            CGRect(x: 60, y: 30, width: 100, height: 40)
        )
    }

    func testDisplayLocalSourceRectConvertsWindowFrameToDisplayPixels() throws {
        let rect = try XCTUnwrap(ScreenCaptureGeometry.displayLocalSourceRect(
            for: CGRect(x: 150, y: 250, width: 400, height: 300),
            displayFrame: CGRect(x: 100, y: 200, width: 1000, height: 500),
            displayPixelSize: CGSize(width: 2000, height: 1000)
        ))

        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    func testDisplayLocalSourceRectClipsToDisplayFrame() throws {
        let rect = try XCTUnwrap(ScreenCaptureGeometry.displayLocalSourceRect(
            for: CGRect(x: 50, y: 150, width: 200, height: 200),
            displayFrame: CGRect(x: 100, y: 200, width: 1000, height: 500),
            displayPixelSize: CGSize(width: 2000, height: 1000)
        ))

        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 300, height: 300))
    }
}
