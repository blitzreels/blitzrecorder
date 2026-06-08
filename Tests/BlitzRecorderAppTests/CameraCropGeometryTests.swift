import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class CameraCropGeometryTests: XCTestCase {
    func testCropFrameUsesRenderGeometrySourceFrame() {
        let geometry = makeGeometry(
            cameraFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceAspectRatio: 16.0 / 9.0
        )

        let sourceFrame = geometry.sourceFrame
        let cropFrame = geometry.cropFrame(amount: .zero, position: .zero)

        XCTAssertRect(sourceFrame, equals: CGRect(x: -38.888888888888886, y: 0, width: 177.77777777777777, height: 100))
        XCTAssertRect(cropFrame, equals: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testMoveClampsCropInsideSourceFrame() {
        let geometry = makeGeometry(
            cameraFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceAspectRatio: 16.0 / 9.0
        )
        let crop = geometry.cropFrame(amount: CGPoint(x: 0.25, y: 0.25), position: .zero)

        let moved = geometry.movedCropFrame(crop, delta: CGPoint(x: 1_000, y: 0))

        XCTAssertEqual(moved.maxX, geometry.sourceFrame.maxX, accuracy: 0.0001)
        XCTAssertEqual(moved.height, crop.height, accuracy: 0.0001)
    }

    func testResizeMaintainsTargetAspectAndMinimumScale() {
        let geometry = makeGeometry(
            cameraFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceAspectRatio: 16.0 / 9.0
        )
        let crop = geometry.cropFrame(amount: .zero, position: .zero)

        let resized = geometry.resizedCropFrame(
            crop,
            delta: CGPoint(x: -1_000, y: 0),
            anchor: .right
        )

        XCTAssertEqual(resized.width / resized.height, geometry.cropAspectRatio, accuracy: 0.0001)
        XCTAssertEqual(resized.width, geometry.baseCropFrame.width * 0.25, accuracy: 0.0001)
    }

    func testControlConvertsCropFrameBackToAmountAndPosition() throws {
        let geometry = makeGeometry(
            cameraFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceAspectRatio: 16.0 / 9.0
        )
        let crop = geometry.cropFrame(
            amount: CGPoint(x: 0.25, y: 0.25),
            position: CGPoint(x: 1, y: 0)
        )

        let control = try XCTUnwrap(geometry.control(for: crop))

        XCTAssertEqual(control.amount.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(control.amount.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(control.position.x, 1, accuracy: 0.0001)
        XCTAssertEqual(control.position.y, 0, accuracy: 0.0001)
    }

    private func makeGeometry(cameraFrame: CGRect, sourceAspectRatio: CGFloat) -> CameraCropGeometry {
        var layout = SceneLayout()
        layout.cameraFrame = cameraFrame
        let scene = RecordingScene(
            enabledSources: [.camera],
            sceneLayout: layout
        )
        return CameraCropGeometry(
            renderGeometry: SceneRenderGeometry(
                canvas: CGRect(x: 0, y: 0, width: 100, height: 100),
                scene: scene,
                origin: .lowerLeft
            ),
            sourceAspectRatio: sourceAspectRatio
        )
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
