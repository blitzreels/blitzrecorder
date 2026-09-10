import XCTest
@testable import BlitzRecorderApp

final class CursorPresentationCacheTests: XCTestCase {
    func testSpritesReuseArtworkAcrossPositionAndScaleChangesButKeepClickAnimation() throws {
        let original = try XCTUnwrap(CursorPresentationRenderer.sprite(.init(
            sample: .init(position: .zero, clickAge: 1, rotation: 0), style: .standard,
            sourceFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))))
        let moved = try XCTUnwrap(CursorPresentationRenderer.sprite(.init(
            sample: .init(position: CGPoint(x: 0.5, y: 0.5), clickAge: 2, rotation: 0), style: .init(scale: 3),
            sourceFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))))
        XCTAssertTrue(original.image === moved.image)
        XCTAssertEqual(moved.frame.midX, 960)
        XCTAssertEqual(moved.frame.width, original.frame.width * 2)
        let clicked = try XCTUnwrap(CursorPresentationRenderer.sprite(.init(
            sample: .init(position: .zero, clickAge: 0.15, rotation: 0), style: .standard,
            sourceFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))))
        XCTAssertFalse(original.image === clicked.image)
        let clicksDisabled = try XCTUnwrap(CursorPresentationRenderer.sprite(.init(
            sample: .init(position: .zero, clickAge: 0.15, rotation: 0), style: .init(emphasizesClicks: false),
            sourceFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))))
        XCTAssertTrue(original.image === clicksDisabled.image)
    }

    func testLoaderTracksSourceChangesAndTrimOffsets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("cursor-track.json")
        let track = RecordingCursorTrack(version: 2, samples: [
            .init(time: 1, x: 0.2, y: 0.3, clicked: true, rendered: true),
            .init(time: 2, x: 0.8, y: 0.3, clicked: true, rendered: true)
        ])
        try JSONEncoder().encode(track).write(to: url)
        let loader = CursorPresentationLoader()
        let first = await loader.load(.init(directory: root, trimOffset: 0))
        let trimmed = await loader.load(.init(directory: root, trimOffset: 1))
        XCTAssertEqual(first.sample(.init(time: 1, style: .standard))?.position.x, 0.2)
        XCTAssertEqual(trimmed.sample(.init(time: 1, style: .standard))?.position.x, 0.8)
        try JSONEncoder().encode(RecordingCursorTrack(version: 2, samples: [])).write(to: url)
        let replaced = await loader.load(.init(directory: root, trimOffset: 1))
        XCTAssertTrue(replaced.isEmpty)
    }
}
