import XCTest
@testable import BlitzRecorderApp

final class PrivacyCanvasGeometryTests: XCTestCase {
    func testSourceCoordinatesMatchLetterboxedCanvas() throws {
        var settings = RecordingSettings()
        settings.layout = .square
        settings.enabledSources = [.screen]
        settings.screenContentMode = .fit
        settings.canvasPadding = 0
        settings.sceneLayout = SceneLayout.presetLayout(.screenFullscreen, for: .square)
        let scene = RecordingScene(settings: settings)
        let sources = PrivacyCanvasGeometry.sources(.init(size: CGSize(width: 600, height: 600),
            renderSize: CGSize(width: 1080, height: 1080), scene: scene, aspectRatios: [.screen: 2], hiddenKinds: []))
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.frame.minX, 0, accuracy: 0.01)
        XCTAssertEqual(source.frame.minY, 150, accuracy: 0.01)
        XCTAssertEqual(source.frame.width, 600, accuracy: 0.01)
        XCTAssertEqual(source.frame.height, 300, accuracy: 0.01)
        let point = source.pointInSource(CGPoint(x: 120, y: 180))
        XCTAssertEqual(point.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.1, accuracy: 0.001)
        let mask = PrivacyMask(id: UUID(), source: .screen, frame: CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.2),
                               start: 0, end: 10, style: .cover)
        let displayed = source.displayedFrame(mask)
        XCTAssertEqual(displayed.minX, 120, accuracy: 0.01)
        XCTAssertEqual(displayed.minY, 180, accuracy: 0.01)
        XCTAssertEqual(displayed.width, 180, accuracy: 0.01)
        XCTAssertEqual(displayed.height, 60, accuracy: 0.01)
    }

    func testDrawingAndMovingStayInsideOriginalSource() {
        let original = CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.2)
        let moved = PrivacyCanvasGeometry.changedFrame(.init(frame: original, start: .zero,
            current: CGPoint(x: 1, y: -1), gesture: .move))
        XCTAssertEqual(moved.minX, 0.7, accuracy: 0.001)
        XCTAssertEqual(moved.minY, 0, accuracy: 0.001)
        XCTAssertEqual(moved.size, original.size)
        let drawn = PrivacyCanvasGeometry.changedFrame(.init(frame: .zero, start: CGPoint(x: 0.7, y: 0.8),
            current: CGPoint(x: 0.2, y: 0.1), gesture: .draw))
        XCTAssertEqual(drawn.minX, 0.2, accuracy: 0.001)
        XCTAssertEqual(drawn.minY, 0.1, accuracy: 0.001)
        XCTAssertEqual(drawn.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(drawn.height, 0.7, accuracy: 0.001)
    }

    func testResizeKeepsOppositeCornerAndCannotInvert() {
        let original = CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.2)
        let resized = PrivacyCanvasGeometry.changedFrame(.init(frame: original, start: .zero,
            current: CGPoint(x: -0.1, y: -0.05), gesture: .resize(.topLeft)))
        XCTAssertEqual(resized.maxX, original.maxX, accuracy: 0.001)
        XCTAssertEqual(resized.maxY, original.maxY, accuracy: 0.001)
        XCTAssertEqual(resized.minX, 0.1, accuracy: 0.001)
        let inverted = PrivacyCanvasGeometry.changedFrame(.init(frame: original, start: .zero,
            current: CGPoint(x: -1, y: -1), gesture: .resize(.bottomRight)))
        XCTAssertGreaterThanOrEqual(inverted.width, 0.0049)
        XCTAssertGreaterThanOrEqual(inverted.height, 0.0049)
    }
}
