import XCTest
@testable import BlitzRecorderApp

final class EditorVideoClipTimelineTests: XCTestCase {
    func testRightEdgeShortensUncutAndCutClipsWhileKeepingTheNextClipIntact() throws {
        for gap in [0.0, 3.0] {
            var original = TimelineEdits.empty
            original.videoSplits = [4 + gap]
            if gap > 0 { original.cuts = [.init(start: 4, end: 4 + gap, kind: .silence, source: .automatic)] }
            let result = EditorVideoCuts.dragRight(.init(
                edits: original, clip: .init(start: 0, end: 4), nextClipStart: 4 + gap,
                duration: 10, delta: -1.25))
            let edits = try XCTUnwrap(result.edits)
            XCTAssertEqual(result.selection, .init(start: 0, end: 2.75))
            let layout = EditorClipSpine.layout(.init(edits: edits, duration: 10))
            XCTAssertEqual(layout.clips.map(\.range), [.init(start: 0, end: 2.75), .init(start: 4 + gap, end: 10)])
            XCTAssertEqual(layout.clips.map(\.start), [0, 2.75])
            XCTAssertEqual(layout.clips.first?.id, .init(takeStart: 0))
            XCTAssertEqual(layout.clips.last?.id, .init(takeStart: 4 + gap))
            XCTAssertEqual(EditorTimelineProjection(.init(duration: 10, cuts: edits.cuts)).duration, 8.75 - gap)
            XCTAssertEqual(edits.videoSplits, original.videoSplits)
        }
    }

    func testInwardTrimAcceptsOneTimelineTickAtFractionalBoundaries() throws {
        for end in [4.0, 8.1, 17.0 / 3, 601.0 / 600] {
            let result = EditorVideoCuts.dragRight(.init(
                edits: .empty, clip: .init(start: 0, end: end), nextClipStart: nil,
                duration: end, delta: -1.0 / 600))
            let edits = try XCTUnwrap(result.edits)
            XCTAssertEqual(result.selection.end, end - 1.0 / 600, accuracy: 1e-9)
            XCTAssertEqual(EditorTimelineProjection(.init(duration: end, cuts: edits.cuts)).duration,
                           end - 1.0 / 600, accuracy: 1e-9)
            let restored = EditorVideoCuts.dragRight(.init(
                edits: edits, clip: result.selection, nextClipStart: nil, duration: end, delta: 1.0 / 600))
            XCTAssertEqual(restored.selection.end, end, accuracy: 1e-9)
            XCTAssertEqual(EditorTimelineProjection(.init(duration: end, cuts: try XCTUnwrap(restored.edits).cuts)).duration,
                           end, accuracy: 1e-9)
        }
    }

    func testTrimReversesDirectionAndReturnsToOriginWithoutAccumulatingCuts() throws {
        var original = TimelineEdits.empty
        original.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        for scale: CGFloat in [25, 100, 400] {
            var session = EditorClipTrimSession()
            let origin = EditorClipTrimSession.Origin(edits: original, clip: .init(start: 0, end: 4),
                nextClipStart: 7, pixelsPerSecond: scale, duration: 10)
            session.beginTrim(.init(origin: origin, displayDuration: 7))
            for delta in [2.0, -1.0, 1.0, -2.0, 0.0] {
                let range = try XCTUnwrap(session.applyTrim(translationWidth: CGFloat(delta) * scale))
                XCTAssertEqual(range, .init(start: 0, end: 4 + delta))
                let edits = session.edits(committed: original)
                XCTAssertEqual(EditorTimelineProjection(.init(duration: 10, cuts: edits.cuts)).duration, 7 + delta)
                XCTAssertEqual(session.lockedDisplayDuration, 7)
                session.beginTrim(.init(origin: .init(edits: edits, clip: range, nextClipStart: 7,
                    pixelsPerSecond: scale / 2, duration: 10), displayDuration: 7 + delta))
                XCTAssertEqual(session.origin, origin)
            }
            XCTAssertEqual(session.edits(committed: original), original)
            XCTAssertNil(session.finish())
            XCTAssertFalse(session.isActive)
        }
    }

    func testShorteningTheLastClipClampsBeforeItDisappearsAndCanBeRestored() throws {
        for clip in [EditorTimeRange(start: 0, end: 10), .init(start: 9, end: 10)] {
            var original = TimelineEdits.empty
            if clip.start > 0 { original.cuts = [.init(start: 0, end: clip.start, kind: .manual, source: .user)] }
            for delta in [-100.0, -Double.greatestFiniteMagnitude] {
                let result = EditorVideoCuts.dragRight(.init(
                    edits: original, clip: clip, nextClipStart: nil, duration: 10, delta: delta))
                let edits = try XCTUnwrap(result.edits)
                XCTAssertEqual(result.selection.duration, 0.1, accuracy: 1e-9)
                XCTAssertEqual(EditorTimelineProjection(.init(duration: 10, cuts: edits.cuts)).duration, 0.1, accuracy: 1e-9)
                let restored = EditorVideoCuts.dragRight(.init(
                    edits: edits, clip: result.selection, nextClipStart: nil, duration: 10, delta: 100))
                XCTAssertEqual(restored.selection, clip)
                XCTAssertEqual(EditorClipSpine.layout(.init(edits: try XCTUnwrap(restored.edits), duration: 10)).clips.map(\.range), [clip])
            }
        }
    }

    func testCancelledInwardTrimCannotLeakIntoTheNextGesture() throws {
        let original = TimelineEdits.empty
        var session = EditorClipTrimSession()
        let origin = EditorClipTrimSession.Origin(edits: original, clip: .init(start: 0, end: 10),
            nextClipStart: nil, pixelsPerSecond: 100, duration: 10)
        session.beginTrim(.init(origin: origin, displayDuration: 10))
        XCTAssertEqual(session.applyTrim(translationWidth: -200), .init(start: 0, end: 8))
        _ = session.finish()
        XCTAssertEqual(session.edits(committed: original), original)
        session.beginTrim(.init(origin: origin, displayDuration: 10))
        XCTAssertEqual(session.applyTrim(translationWidth: -100), .init(start: 0, end: 9))
        let committed = try XCTUnwrap(session.finish())
        XCTAssertEqual(committed.enabledCuts.map(\.start), [9])
        XCTAssertEqual(committed.enabledCuts.map(\.end), [10])
    }

    func testRestoredFootageCanBeSplitAndDeletedAgainWithoutReopening() throws {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        let extended = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 2
        )))
        let split = try XCTUnwrap(EditorVideoCuts.splitting(.init(edits: extended, time: 5, duration: 10)))
        let layout = EditorClipSpine.layout(.init(edits: split, duration: 10))
        XCTAssertEqual(layout.clips.map(\.range), [
            .init(start: 0, end: 5), .init(start: 5, end: 6), .init(start: 7, end: 10)
        ])
        let selected = try XCTUnwrap(EditorVideoCuts.range(.init(edits: split, time: 5.5, duration: 10)))
        XCTAssertEqual(selected, .init(start: 5, end: 6))
        let deleted = try XCTUnwrap(EditorTimeRange.removing(.init(range: selected, edits: split, takeDuration: 10)))
        XCTAssertEqual(TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: deleted.cuts).outputDuration.seconds, 8)
    }

    func testRestoredBoundarySweepMatchesOverlappingIntervalReference() {
        for seed in 0..<100 {
            var edits = TimelineEdits.empty
            let suggestions: [TimelineCut] = (0..<50).map {
                .init(start: Double($0), end: Double($0) + 0.5, kind: .silence, source: .automatic)
            }
            edits.cuts = (0..<30).map { index in
                let start = Double((seed * 17 + index * 13) % 90) / 2
                return .init(start: start, end: start + Double(index % 9 + 1),
                             kind: .manual, source: .user, isEnabled: index % 4 == 0)
            }
            let expected = suggestions.flatMap { [$0.start, $0.end] }.filter { time in
                !edits.cuts.contains { !$0.isEnabled && time >= $0.start && time < $0.end }
            }
            XCTAssertEqual(EditorClipSpine.boundaries(.init(edits: edits, duration: 50, silenceCuts: suggestions)), expected)
        }
    }

    func testCancelledExtensionCannotLeakIntoTheNextDrag() throws {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        var session = EditorClipTrimSession()
        let origin = EditorClipTrimSession.Origin(edits: edits, clip: .init(start: 0, end: 4),
            nextClipStart: 7, pixelsPerSecond: 100, duration: 10)
        session.beginTrim(.init(origin: origin, displayDuration: 7))
        XCTAssertEqual(session.applyTrim(translationWidth: 200), .init(start: 0, end: 6))
        _ = session.finish()
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.edits(committed: edits), edits)
        session.beginTrim(.init(origin: origin, displayDuration: 7))
        XCTAssertEqual(session.applyTrim(translationWidth: 100), .init(start: 0, end: 5))
        let committed = try XCTUnwrap(session.finish())
        XCTAssertEqual(committed.enabledCuts.map(\.start), [5])
        XCTAssertFalse(session.isActive)
    }

    func testDenseRestoredBoundariesRemainResponsive() {
        let count = 10_000
        var edits = TimelineEdits.empty
        let suggestions: [TimelineCut] = (0..<count).map {
            .init(start: Double($0 * 3), end: Double($0 * 3 + 2), kind: .silence, source: .automatic)
        }
        edits.cuts = (0..<count).map {
            .init(start: Double($0 * 3), end: Double($0 * 3 + 1), kind: .manual, source: .user, isEnabled: false)
        }
        let start = ProcessInfo.processInfo.systemUptime
        let times = EditorClipSpine.boundaries(.init(edits: edits, duration: Double(count * 3), silenceCuts: suggestions))
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(Set(times).count, count)
        print("EDITOR_PERF restored-boundaries count=\(count) seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, 1)
    }

    func testFullyRestoringCutPreservesTheNextClipWithoutAnExplicitSplit() throws {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        let restored = try XCTUnwrap(EditorVideoCuts.extendingRight(.init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: 3
        )))
        XCTAssertEqual(EditorClipSpine.layout(.init(edits: restored, duration: 10)).clips.map(\.range), [
            .init(start: 0, end: 7), .init(start: 7, end: 10)
        ])
    }

    func testInvalidDragDoesNotMoveTheSelectionOrRestoreFootage() {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        for delta in [Double.infinity, -Double.infinity, Double.nan] {
            let result = EditorVideoCuts.dragRight(.init(
                edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7, duration: 10, delta: delta
            ))
            XCTAssertNil(result.edits)
            XCTAssertEqual(result.selection, .init(start: 0, end: 4))
        }
    }

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

    func testDragReturningToOriginClearsDraftWithoutUnlockingScaleUntilFinished() {
        var committed = TimelineEdits.empty
        committed.cuts = [.init(start: 4, end: 7, kind: .manual, source: .user)]
        var session = EditorClipTrimSession()
        XCTAssertFalse(session.isActive)
        session.beginTrim(.init(origin: .init(edits: committed, clip: .init(start: 0, end: 4),
            nextClipStart: 7, pixelsPerSecond: 100, duration: 10), displayDuration: 7))
        _ = session.applyTrim(translationWidth: 100)
        XCTAssertNotEqual(session.edits(committed: committed), committed)
        _ = session.applyTrim(translationWidth: 0)
        XCTAssertEqual(session.lockedDisplayDuration, 7)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.edits(committed: committed), committed)
        XCTAssertNil(session.finish())
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.lockedDisplayDuration)
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
        session.beginTrim(.init(origin: .init(
            edits: edits, clip: .init(start: 0, end: 4), nextClipStart: 7,
            pixelsPerSecond: 100, duration: 10
        ), displayDuration: 7))
        XCTAssertEqual(session.applyTrim(translationWidth: 200), .init(start: 0, end: 6))
        XCTAssertEqual(session.edits(committed: edits).videoSplits, [7])
        let committed = try XCTUnwrap(session.finish())
        XCTAssertEqual(committed.videoSplits, [7])
        XCTAssertEqual(
            EditorClipSpine.layout(.init(edits: committed, duration: 10)).clips.map(\.start),
            [0, 6]
        )
    }

    func testSeekTimesKeepExplicitSplitsAndSuppressRestoredSilenceBoundaries() {
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
        XCTAssertEqual(times, [1, 4, 6])
        XCTAssertEqual(times.filter { abs($0 - 4) <= 1.0 / 600 }.count, 1)
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
        XCTAssertEqual(EditorTimelineClipPointer.at(request(391)), .pointingHand)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(392)), .resize)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(395)), .resize)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(400)), .resize)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(403)), .resize)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(404)), .resize)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(500)), .pointingHand)
        XCTAssertEqual(EditorTimelineClipPointer.at(request(1_000)), .arrow)
        XCTAssertEqual(
            EditorTimelineClipPointer.at(.init(
                layout: layout, edits: edits, duration: 10, pixelsPerSecond: 100, x: 200, isTrimming: true
            )),
            .resize
        )
    }

    func testResizePointerSupportsShorteningWithoutRestorableFootage() {
        var edits = TimelineEdits.empty
        edits.videoSplits = [4]
        edits.cuts = [.init(start: 8, end: 10, kind: .manual, source: .user)]
        let layout = EditorClipSpine.layout(.init(edits: edits, duration: 10))
        for pixelsPerSecond: CGFloat in [25, 100, 400] {
            let pointer = { (x: CGFloat) in
                EditorTimelineClipPointer.at(.init(
                    layout: layout, edits: edits, duration: 10, pixelsPerSecond: pixelsPerSecond, x: x))
            }
            XCTAssertEqual(pointer(4 * pixelsPerSecond - 3), .resize)
            XCTAssertEqual(pointer(4 * pixelsPerSecond + 3), .resize)
            XCTAssertEqual(pointer(8 * pixelsPerSecond - 3), .resize)
            XCTAssertEqual(pointer(8 * pixelsPerSecond + 3), .resize)
            XCTAssertEqual(pointer(8 * pixelsPerSecond + 4), .arrow)
        }
    }
}

extension EditorVideoClipTimelineTests {
    func testLeftEdgeRestoresOnlyTheGapAndPreservesPreviousClip() throws {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 2, end: 5, kind: .manual, source: .user)]
        edits.videoSplits = [2, 5]
        let result = EditorClipSpine.dragLeft(.init(edits: edits, clip: .init(start: 5, end: 8),
            previousClipEnd: 2, duration: 10, delta: -20))
        let restored = try XCTUnwrap(result.edits)
        XCTAssertEqual(result.selection, .init(start: 2, end: 8))
        XCTAssertTrue(restored.enabledCuts.isEmpty)
        let clips = EditorClipSpine.layout(.init(edits: restored, duration: 10)).clips
        XCTAssertEqual(clips.first?.range, .init(start: 0, end: 2))
        XCTAssertEqual(clips.count, 2)
    }

    func testLeftTrimReversesWithoutChangingItsOriginOrScale() throws {
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 2, end: 5, kind: .manual, source: .user)]
        var session = EditorClipTrimSession()
        let origin = EditorClipTrimSession.Origin(edits: edits, clip: .init(start: 5, end: 8),
            nextClipStart: nil, pixelsPerSecond: 100, duration: 10, edge: .left, previousClipEnd: 2)
        session.beginTrim(.init(origin: origin, displayDuration: 7))
        XCTAssertEqual(session.applyTrim(translationWidth: -200), .init(start: 3, end: 8))
        XCTAssertEqual(session.applyTrim(translationWidth: 500), .init(start: 7.9, end: 8))
        XCTAssertEqual(session.origin, origin)
        XCTAssertEqual(session.lockedDisplayDuration, 7)
        XCTAssertEqual(session.applyTrim(translationWidth: 0), origin.clip)
        XCTAssertNil(session.finish())
    }

    func testDeletingAndRestoringDoNotRequestASeekToTheSelection() throws {
        let cut = try XCTUnwrap(EditorTimelineWrite.cuttingTogether(
            ranges: [.init(start: 1, end: 3)], edits: .empty, takeDuration: 10))
        XCTAssertNil(cut.seek)
        XCTAssertTrue(cut.clearSelection)
        XCTAssertEqual(cut.edits.enabledCuts.first?.start, 1)
        let restore = try XCTUnwrap(EditorTimelineWrite.restoringTogether(
            ranges: [.init(start: 1, end: 3)], edits: cut.edits, takeDuration: 10))
        XCTAssertNil(restore.seek)
        XCTAssertTrue(restore.edits.enabledCuts.isEmpty)
    }
}
