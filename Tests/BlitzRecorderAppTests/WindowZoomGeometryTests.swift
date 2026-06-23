import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class WindowZoomGeometryTests: XCTestCase {
    func testVisualZoomInUsesSmallerSourceFrame() {
        let frame = WindowZoomGeometry.sourceFrame(
            for: CGRect(x: 100, y: 200, width: 500, height: 300),
            zoom: 1.25
        )

        XCTAssertRect(frame, equals: CGRect(x: 150, y: 230, width: 400, height: 240))
    }

    func testVisualZoomOutUsesLargerSourceFrame() {
        let frame = WindowZoomGeometry.sourceFrame(
            for: CGRect(x: 100, y: 200, width: 500, height: 300),
            zoom: 0.75
        )

        XCTAssertRect(
            frame,
            equals: CGRect(
                x: 16.6666666667,
                y: 150,
                width: 666.6666666667,
                height: 400
            )
        )
    }

    func testZoomIsClamped() {
        XCTAssertEqual(WindowZoomGeometry.clampedZoom(0.1), WindowZoomGeometry.minimumZoom)
        XCTAssertEqual(WindowZoomGeometry.clampedZoom(3), WindowZoomGeometry.maximumZoom)
    }
}

private func XCTAssertRect(
    _ actual: CGRect,
    equals expected: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
}
