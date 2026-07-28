import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class ScreenSourceZoomGeometryTests: XCTestCase {
    func testUiScaleKeepsTheFullSourceVisible() {
        var settings = RecordingSettings()
        settings.screenWindowZoom = 2

        XCTAssertNil(ScreenCaptureGeometry.effectiveCrop(for: settings))
    }

    func testUiScaleKeepsManualCropUnchanged() {
        var settings = RecordingSettings()
        settings.screenCrop = CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.7)
        settings.screenWindowZoom = 2

        XCTAssertEqual(ScreenCaptureGeometry.effectiveCrop(for: settings), settings.screenCrop)
    }

    func testFitFullWindowUsesEntireAvailableSceneSlotHeight() {
        let plan = TargetWindowFitting.plan(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 30, width: 1920, height: 1050),
            captureLayout: .horizontal,
            screenSlot: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1),
            canvasPadding: 0,
            zoom: 1
        )

        XCTAssertEqual(plan.windowFrame.height, 1050, accuracy: 0.0001)
        XCTAssertEqual(ScreenSourceZoomGeometry.clamped(2), 2)
    }

    func testTwoXUiScaleHalvesThePhysicalSourceWindow() {
        let frame = WindowZoomGeometry.sourceFrame(
            for: CGRect(x: 0, y: 0, width: 1280, height: 720),
            zoom: 2
        )

        XCTAssertEqual(frame.width, 640, accuracy: 0.0001)
        XCTAssertEqual(frame.height, 360, accuracy: 0.0001)
    }

    func testHalfUiScaleIsAccepted() {
        XCTAssertEqual(ScreenSourceZoomGeometry.clamped(0.5), 0.5, accuracy: 0.0001)
    }

    func testCropScalesInsideExistingSourceRect() {
        let result = ScreenCaptureGeometry.croppedSourceRect(request: .init(
            sourceRect: CGRect(x: 100, y: 50, width: 800, height: 600),
            normalizedCrop: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.5)
        ))

        XCTAssertEqual(result, CGRect(x: 180, y: 170, width: 640, height: 300))
    }
}
