import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class SceneLayerResizingTests: XCTestCase {
    func testAspectLockedHeightResizePreservesAspectRatio() {
        let frame = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3)

        let resized = SceneLayerResizing.resized(
            frame,
            delta: CGPoint(x: 0, y: 0.1),
            anchor: .top,
            aspectRatio: frame.width / frame.height
        )

        XCTAssertRect(
            resized,
            equals: CGRect(x: 0.0333333333, y: 0.2, width: 0.5333333333, height: 0.4)
        )
    }

    func testCameraResizeDoesNotRequireScreenAdjustment() {
        var layout = SceneLayout()
        layout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.24)

        layout.cameraFrame = SceneLayerResizing.resized(
            layout.cameraFrame,
            delta: CGPoint(x: 0, y: 0.2),
            anchor: .top
        )

        XCTAssertRect(layout.screenFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertRect(layout.cameraFrame, equals: CGRect(x: 0, y: 0, width: 1, height: 0.44))
    }

    func testClampsMinimumSizeWithoutChangingOtherAxis() {
        let frame = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.3)

        let resized = SceneLayerResizing.resized(
            frame,
            delta: CGPoint(x: 0.18, y: 0),
            anchor: .left
        )

        XCTAssertRect(
            resized,
            equals: CGRect(x: 0.32, y: 0.2, width: 0.08, height: 0.3)
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
