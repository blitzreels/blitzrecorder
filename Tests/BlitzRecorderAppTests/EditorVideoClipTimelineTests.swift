import XCTest
@testable import BlitzRecorderApp

final class EditorVideoClipTimelineTests: XCTestCase {
    func testSilenceCutsAndBladeSplitsBothCutTheClipRow() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [6]
        let layout = EditorClipSpine.layout(.init(
            edits: edits, duration: 10,
            silenceCuts: [.init(start: 2, end: 4, kind: .silence, source: .automatic)]
        ))
        XCTAssertEqual(layout.clips.map(\.range), [
            .init(start: 0, end: 2), .init(start: 2, end: 4), .init(start: 4, end: 6), .init(start: 6, end: 10)
        ])
        let bladed = try XCTUnwrap(EditorVideoCuts.splitting(.init(
            edits: edits, time: 5, duration: 10, silenceCuts: [
                .init(start: 2, end: 4, kind: .silence, source: .automatic)
            ]
        )))
        XCTAssertEqual(bladed.videoSplits, [5, 6])
        XCTAssertEqual(
            EditorVideoCuts.range(.init(edits: bladed, time: 5.2, duration: 10, silenceCuts: [
                .init(start: 2, end: 4, kind: .silence, source: .automatic)
            ])),
            .init(start: 5, end: 6)
        )
    }

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

    func testExtendingAClipRestoresTheCutUntilTheNextClipAndRemovesTheOldOutSplit() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4, 7]
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        XCTAssertEqual(
            EditorVideoCuts.rightExpandLimit(.init(edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10)),
            7
        )
        XCTAssertNil(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 0
        )))
        let partial = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 2
        )))
        XCTAssertEqual(partial.videoSplits, [7])
        XCTAssertEqual(partial.enabledCuts.map(\.start), [6])
        XCTAssertEqual(partial.enabledCuts.map(\.end), [7])
        let layout = EditorClipSpine.layout(.init(edits: partial, duration: 10))
        XCTAssertEqual(layout.clips.map(\.range), [.init(start: 0, end: 6), .init(start: 7, end: 10)])
        let full = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 100
        )))
        XCTAssertTrue(full.enabledCuts.isEmpty)
        XCTAssertEqual(full.videoSplits, [7])
        XCTAssertNil(EditorVideoCuts.extendingRight(.init(
            edits: full, clip: .init(start: 0, end: 7), nextClipStart: 7, duration: 10, delta: 2
        )))
    }

    func testBladeOnlyClipsCannotExtendAndATrailingCutCan() throws {
        var split = TimelineEdits.empty
        split.videoSplits = [4]
        XCTAssertNil(EditorVideoCuts.rightExpandLimit(.init(
            edits: split, clip: .init(start: 0, end: 4), nextClipStart: 4, duration: 10
        )))
        var trailing = TimelineEdits.empty
        trailing.cuts = [.init(start: 6, end: 10, kind: .manual, source: .user)]
        let extended = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: trailing, clip: .init(start: 0, end: 6), nextClipStart: nil, duration: 10, delta: 2.5
        )))
        XCTAssertEqual(extended.cuts.filter(\.isEnabled).map(\.start), [8.5])
        XCTAssertEqual(TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: extended.cuts).outputDuration.seconds, 8.5, accuracy: 0.001)
    }

    func testRestoredSilenceBoundaryDoesNotSplitAnExtendedClip() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4]
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        let extended = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 2
        )))
        let layout = EditorClipSpine.layout(.init(
            edits: extended, duration: 10,
            silenceCuts: [.init(start: 4, end: 6, kind: .silence, source: .automatic)]
        ))
        XCTAssertEqual(layout.clips.map(\.range), [.init(start: 0, end: 6), .init(start: 7, end: 10)])
        XCTAssertEqual(layout.clips.first?.id, EditorVideoClipLayout.Clip.ID(takeStart: 0))
        XCTAssertEqual(layout.clips.first?.index, 0)
        XCTAssertEqual(layout.clips.last?.index, 1)
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

    func testClipIdentityUsesTakeStartAndSurvivesARightExtend() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4, 7]
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        let before = EditorClipSpine.layout(.init(edits: edits, duration: 10))
        XCTAssertEqual(before.clips.map(\.index), [0, 1])
        XCTAssertEqual(before.clips.map(\.id), [
            .init(takeStart: 0), .init(takeStart: 7)
        ])
        let extended = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 2
        )))
        let after = EditorClipSpine.layout(.init(edits: extended, duration: 10))
        XCTAssertEqual(after.clips.first?.id, before.clips.first?.id)
        XCTAssertEqual(after.clips.last?.id, before.clips.last?.id)
        XCTAssertEqual(after.next(after: after.clips[0])?.range.start, 7)
    }

    func testLeadingCutDoesNotGiveTheFirstVisibleClipASeamIndex() {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 0, end: 3, kind: .manual, source: .user)]
        let layout = EditorClipSpine.layout(.init(edits: edits, duration: 10))
        XCTAssertEqual(layout.clips.first?.index, 0)
        XCTAssertEqual(layout.clips.first?.id, .init(takeStart: 3))
        XCTAssertEqual(layout.clips.first?.range, .init(start: 3, end: 10))
    }

    func testTrimSessionPreviewsDraftEditsThenRestoresCommittedOnFinish() {
        var committed = TimelineEdits.empty
        committed.videoSplits = [4]
        var draft = committed
        draft.videoSplits = [4, 6]
        var session = EditorClipTrimSession()
        XCTAssertFalse(session.isActive)
        session.preview(draft, currentDisplayDuration: 10)
        XCTAssertEqual(session.lockedDisplayDuration, 10)
        XCTAssertEqual(session.edits(committed: committed).videoSplits, [4, 6])
        session.preview(nil, currentDisplayDuration: 12)
        XCTAssertEqual(session.lockedDisplayDuration, 10)
        XCTAssertEqual(session.edits(committed: committed).videoSplits, [4])
        XCTAssertNil(session.finish())
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.edits(committed: committed).videoSplits, [4])
    }

    func testDraggingRightRestoresTheCutAndPushesTheNextClip() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4, 7]
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        let before = EditorClipSpine.layout(.init(edits: edits, duration: 10))
        XCTAssertEqual(before.clips.map(\.range), [.init(start: 0, end: 4), .init(start: 7, end: 10)])
        XCTAssertEqual(before.clips.map(\.start), [0, 4])
        let dragged = EditorVideoCuts.dragRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 2
        ))
        XCTAssertEqual(dragged.selection, .init(start: 0, end: 6))
        let after = EditorClipSpine.layout(.init(edits: try XCTUnwrap(dragged.edits), duration: 10))
        XCTAssertEqual(after.clips.map(\.range), [.init(start: 0, end: 6), .init(start: 7, end: 10)])
        XCTAssertEqual(after.clips.map(\.start), [0, 6])
        XCTAssertEqual(
            EditorVideoCuts.dragRight(.init(
                edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 0
            )).edits,
            nil
        )
        XCTAssertNil(EditorVideoCuts.dragRight(.init(
            edits: edits, clip: .init(start: 7, end: 10), nextClipStart: nil, duration: 10, delta: 2
        )).edits)
    }

    func testOutlineExpandSessionGrowsTheSelectedClipThenCommits() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4, 7]
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        var session = EditorClipTrimSession()
        session.beginExpand(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7,
            pixelsPerSecond: 100, duration: 10
        ), currentDisplayDuration: 7)
        XCTAssertEqual(session.applyExpand(translationWidth: 200), .init(start: 0, end: 6))
        XCTAssertEqual(session.edits(committed: edits).videoSplits, [7])
        let committed = try XCTUnwrap(session.finish())
        XCTAssertEqual(committed.videoSplits, [7])
        XCTAssertEqual(
            EditorClipSpine.layout(.init(edits: committed, duration: 10)).clips.map(\.start),
            [0, 6]
        )
    }

    func testSeekTimesUseClipBoundariesAndSceneEventsNotRawVideoSplits() {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4]
        edits.cuts = [
            .init(start: 4, end: 6, kind: .manual, source: .user, isEnabled: false)
        ]
        let times = EditorClipSpine.seekTimes(.init(
            edits: edits, duration: 10,
            silenceCuts: [.init(start: 4, end: 6, kind: .silence, source: .automatic)],
            sceneEventTimes: [1]
        ))
        XCTAssertEqual(times, [1, 6])
        XCTAssertFalse(times.contains { abs($0 - 4) <= 1.0 / 600 })
        XCTAssertEqual(
            EditorClipSpine.seekTimes(.init(
                edits: edits, duration: 10,
                silenceCuts: [.init(start: 4, end: 6, kind: .silence, source: .automatic)],
                sceneEventTimes: [1]
            )),
            times
        )
    }

    func testClipPointerUsesResizeOnExpandableTrailingEdge() {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4, 7]
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        let layout = EditorClipSpine.layout(.init(edits: edits, duration: 10))
        let request = {
            EditorTimelineClipPointer.Request(
                layout: layout, edits: edits, duration: 10, pixelsPerSecond: 100, x: $0)
        }
        XCTAssertEqual(EditorTimelineClipPointer.at(request(200)), .pointingHand)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(395)), .resize)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(500)), .pointingHand)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(1_000)), .arrow)
        XCTAssertEqual(
            EditorTimelineClipPointer.at(.init(
                layout: layout, edits: edits, duration: 10, pixelsPerSecond: 100, x: 200, isExpanding: true
            )),
            .resize
        )
    }

    func testClipSeamsStayHiddenUntilAClipIsHovered() {
        let layout = EditorVideoClipLayout(.init(
            projection: .init(.init(duration: 10, cuts: [])), splits: [4, 7]))
        XCTAssertEqual(layout.hoveredSeamTimes(nil), [])
        XCTAssertEqual(layout.hoveredSeamTimes(layout.clips[0].range), [4])
        XCTAssertEqual(layout.hoveredSeamTimes(layout.clips[1].range), [4, 7])
        XCTAssertEqual(layout.hoveredSeamTimes(layout.clips[2].range), [7])
    }
}
