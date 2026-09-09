import XCTest

@testable import BlitzRecorderApp

final class EditorTimelineRenderingTests: XCTestCase {
    func testDrawingStaysBoundedAtExtremeZoom() {
        let viewport = EditorTimelineViewport.resolve(
            .init(
                offset: 9_500_000,
                viewportWidth: 1_200,
                contentWidth: 14_400_000
            ))
        let cells = EditorTimelineFilmstripCells.visible(.init(width: 14_400_000, frameCount: 192, viewport: viewport))

        XCTAssertLessThanOrEqual(cells.count, 22)
        XCTAssertLessThanOrEqual(viewport.lowerBound, 9_500_000)
        XCTAssertGreaterThanOrEqual(viewport.upperBound, 9_501_200)
        XCTAssertGreaterThan(cells.first?.frameIndex ?? 0, 100)
        XCTAssertTrue(cells.allSatisfy { $0.width <= 84 && $0.frameIndex < 192 })
    }

    func testViewportTilesDoNotChangeDuringSmallScrolls() {
        let first = EditorTimelineViewport.resolve(.init(offset: 520, viewportWidth: 1_024, contentWidth: 20_000))
        let next = EditorTimelineViewport.resolve(.init(offset: 560, viewportWidth: 1_024, contentWidth: 20_000))
        XCTAssertEqual(first, next)
    }

    func testFitAfterZoomClampsStaleScrollOffset() {
        let viewport = EditorTimelineViewport.resolve(.init(offset: 8_000, viewportWidth: 1_200, contentWidth: 1_200))
        XCTAssertEqual(viewport.lowerBound, 0)
        XCTAssertEqual(viewport.upperBound, 1_200)
    }

    func testViewportRejectsInvalidDimensionsAndHandlesOverscroll() {
        let invalid = EditorTimelineViewport.resolve(.init(offset: .nan, viewportWidth: .infinity, contentWidth: 100))
        XCTAssertEqual(invalid.width, 0)
        let before = EditorTimelineViewport.resolve(.init(offset: -40, viewportWidth: 600, contentWidth: 1_200))
        XCTAssertEqual(before.lowerBound, 0)
        let after = EditorTimelineViewport.resolve(.init(offset: 2_000, viewportWidth: 600, contentWidth: 1_200))
        XCTAssertEqual(after.upperBound, 1_200)
    }

    func testFilmstripKeepsFirstAndLastFramesAtRecordingEdges() throws {
        let first = EditorTimelineFilmstripCells.visible(
            .init(
                width: 20_000, frameCount: 16, viewport: .init(lowerBound: 0, upperBound: 1_000)
            ))
        let last = EditorTimelineFilmstripCells.visible(
            .init(
                width: 20_000, frameCount: 16, viewport: .init(lowerBound: 19_000, upperBound: 20_000)
            ))
        XCTAssertEqual(first.first?.frameIndex, 0)
        XCTAssertEqual(last.last?.frameIndex, 15)
        let end = try XCTUnwrap(last.last)
        XCTAssertEqual(end.x + end.width, 20_000, accuracy: 0.001)
    }

    func testMissingFramesAndFullyOffscreenTracksProduceNoCells() {
        let empty = EditorTimelineFilmstripCells.visible(
            .init(
                width: 1_000, frameCount: 0, viewport: .init(lowerBound: 0, upperBound: 500)
            ))
        let offscreen = EditorTimelineFilmstripCells.visible(
            .init(
                width: 500, frameCount: 16, viewport: .init(lowerBound: 500, upperBound: 500)
            ))
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(offscreen.isEmpty)
    }

    func testZoomRequestsUseBoundedCacheTiers() {
        XCTAssertEqual(EditorTimelineFilmstripCells.loadingCount(for: 1_200), 16)
        XCTAssertEqual(EditorTimelineFilmstripCells.loadingCount(for: 1_300), 16)
        XCTAssertEqual(EditorTimelineFilmstripCells.loadingCount(for: 1_400), 32)
        XCTAssertEqual(EditorTimelineFilmstripCells.loadingCount(for: 50_000), 192)
    }

    func testWaveformDownsamplingPreservesShortPeaks() {
        XCTAssertEqual(EditorAudioWaveform(.init(peaks: [0, 1, 0, 0])).amplitude(.init(index: 0, count: 2)), 1)
        XCTAssertEqual(EditorAudioWaveform(.init(peaks: [0, 1, 0, 0])).amplitude(.init(index: 1, count: 2)), 0)
    }

    func testWaveformZoomPreservesTimePositionAndSanitizesInvalidSamples() {
        XCTAssertEqual(EditorAudioWaveform(.init(peaks: [0, 1])).amplitude(.init(index: 6, count: 8)), 1)
        XCTAssertEqual(EditorAudioWaveform(.init(peaks: [0, 1])).amplitude(.init(index: 1, count: 8)), 0)
        XCTAssertEqual(
            EditorAudioWaveform(.init(peaks: [.nan, .infinity, -1])).amplitude(.init(index: 0, count: 1)), 0)
        XCTAssertEqual(EditorAudioWaveform(.init(peaks: [])).amplitude(.init(index: 0, count: 1)), 0)
    }
}
