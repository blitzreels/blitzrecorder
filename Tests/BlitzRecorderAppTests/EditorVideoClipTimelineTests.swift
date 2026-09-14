import XCTest
@testable import BlitzRecorderApp

final class EditorVideoClipTimelineTests: XCTestCase {
    func testCommandBSplitsVisibleClipAtPlayheadAndUndoRestoresOneClip() throws {
        let original = TimelineEdits.empty
        let edits = try XCTUnwrap(EditorVideoCuts.splitting(.init(edits: original, time: 4, duration: 10)))
        let before = EditorVideoClipLayout(.init(projection: .init(.init(duration: 10, cuts: original.cuts)),
            splits: original.videoSplits))
        let after = EditorVideoClipLayout(.init(projection: .init(.init(duration: 10, cuts: edits.cuts)),
            splits: edits.videoSplits))
        XCTAssertEqual(before.clips.count, 1)
        XCTAssertEqual(after.clips.map(\.range), [.init(start: 0, end: 4), .init(start: 4, end: 10)])
        let runs = after.runs(.init(viewport: .init(lowerBound: 0, upperBound: 1000), pixelsPerSecond: 100))
        XCTAssertEqual(runs.map(\.x), [0, 400])
        XCTAssertEqual(runs.map(\.width), [400, 600])
        XCTAssertEqual(after.clip(at: 4)?.title, "Clip 2")
        XCTAssertEqual(before.clip(at: 4)?.title, "Clip 1")
        XCTAssertEqual(after.clips.last?.end, 10)
    }

    func testClipsFollowRippleCutsAndIgnoreSplitsInsideRemovedFootage() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [2, 4, 6, 8, 8, .nan, .infinity, -1, 12]
        edits.cuts = [.init(start: 3, end: 5, kind: .manual, source: .user)]
        let layout = EditorVideoClipLayout(.init(projection: .init(.init(duration: 10, cuts: edits.cuts)),
            splits: edits.videoSplits))
        XCTAssertEqual(layout.clips.map(\.range), [
            .init(start: 0, end: 2), .init(start: 2, end: 3), .init(start: 5, end: 6),
            .init(start: 6, end: 8), .init(start: 8, end: 10)
        ])
        XCTAssertEqual(layout.clips.map(\.start), [0, 2, 3, 4, 6])
        XCTAssertEqual(layout.clip(at: 3)?.range, .init(start: 5, end: 6))
        XCTAssertNil(layout.clip(at: 8))
        XCTAssertNil(layout.clip(at: .nan))
        let selected = try XCTUnwrap(layout.clip(at: 3))
        let deleted = try XCTUnwrap(EditorTimeRange.removing(.init(range: selected.range, edits: edits, takeDuration: 10)))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: deleted.cuts)
        XCTAssertEqual(map.outputDuration.seconds, 7)
        XCTAssertFalse(map.isRemoved(takeTime: 2.5))
        XCTAssertTrue(map.isRemoved(takeTime: 5.5))
        XCTAssertFalse(map.isRemoved(takeTime: 6.5))
    }

    func testShiftSelectsEveryClipAndCommandToggleKeepsOneWhenDeleting() throws {
        let layout = EditorVideoClipLayout(.init(projection: .init(.init(duration: 10, cuts: [])),
            splits: (1..<10).map(Double.init)))
        let ranges = layout.clips.map(\.range)
        let first = SilenceSegmentSelection(ranges[0])
        let all = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: first, target: ranges[9], ranges: ranges, extending: true, toggling: false)))
        XCTAssertEqual(all.ranges, ranges)
        let exceptMiddle = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: all, target: ranges[4], ranges: ranges, extending: false, toggling: true)))
        let deleted = try XCTUnwrap(EditorTimeRange.removingTogether(.init(
            ranges: exceptMiddle.ranges, kind: .manual, edits: .empty, takeDuration: 10)))
        let remaining = EditorVideoClipLayout(.init(projection: .init(.init(duration: 10, cuts: deleted.cuts)),
            splits: (1..<10).map(Double.init)))
        XCTAssertEqual(remaining.clips.map(\.range), [.init(start: 4, end: 5)])
        XCTAssertEqual(remaining.clips.map(\.start), [0])
    }

    func testRemovingClipAtFractionalSplitDoesNotLeavePhantomClip() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [1.2683333333334, 2.6094775533213]
        edits.cuts = [.init(start: edits.videoSplits[0], end: edits.videoSplits[1], kind: .manual, source: .user)]
        let layout = EditorVideoClipLayout(.init(projection: .init(.init(duration: 10, cuts: edits.cuts)),
            splits: edits.videoSplits))
        XCTAssertEqual(layout.clips.count, 2)
        XCTAssertTrue(layout.clips.allSatisfy { $0.end - $0.start >= 1.0 / 600 })
        XCTAssertEqual(EditorVideoCuts.range(.init(edits: edits, time: 3, duration: 10)), layout.clips.last?.range)
    }

    func testDenseClipTimelineKeepsZoomAndScrolledDrawingBoundedToViewport() {
        let layout = EditorVideoClipLayout(.init(projection: .init(.init(duration: 100_000, cuts: [])),
            splits: (1..<100_000).map(Double.init)))
        for scale in [0.01, 0.1, 1, 10, 100] {
            let viewport = EditorTimelineViewport(lowerBound: 400 * scale, upperBound: 400 * scale + 1000)
            let runs = layout.runs(.init(viewport: viewport, pixelsPerSecond: scale))
            XCTAssertLessThanOrEqual(runs.count, 1000)
            XCTAssertLessThanOrEqual(runs.filter { $0.width >= 28 }.count, 36)
            XCTAssertTrue(runs.allSatisfy { $0.x >= 0 && $0.x < 1000 })
        }
        let runs = layout.runs(.init(viewport: .init(lowerBound: 40050, upperBound: 41050), pixelsPerSecond: 100))
        XCTAssertEqual(runs.first?.clip.range, .init(start: 400, end: 401))
        XCTAssertEqual(runs.first?.x, 0)
        XCTAssertEqual(runs.first?.width, 50)
    }
}
