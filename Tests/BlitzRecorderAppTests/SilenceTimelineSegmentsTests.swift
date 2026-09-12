import XCTest

@testable import BlitzRecorderApp

final class SilenceTimelineSegmentsTests: XCTestCase {
    func testSegmentsCoverSoundSilenceAndProtectedSoundWithoutGaps() {
        let segments = SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
            .init(start: 2, end: 4, kind: .silence, source: .automatic),
            .init(start: 6, end: 7, kind: .silence, source: .user, isEnabled: false),
            .init(start: 8, end: 9, kind: .manual, source: .user),
        ]))
        XCTAssertEqual(segments.map(\.range.start), [0, 2, 4, 6, 7])
        XCTAssertEqual(segments.map(\.range.end), [2, 4, 6, 7, 10])
        XCTAssertEqual(segments.map(\.classification), [.sound, .silence, .sound, .sound, .sound])
        XCTAssertEqual(segments.reduce(0) { $0 + $1.range.duration }, 10)
    }

    func testLookupAndNavigationReachTinySegmentsAtExactBoundaries() throws {
        let segments = SilenceTimelineSegments.resolve(.init(duration: 5, cuts: [
            .init(start: 1, end: 2, kind: .silence, source: .automatic),
            .init(start: 2.02, end: 4, kind: .silence, source: .automatic),
        ]))
        let narrow = try XCTUnwrap(SilenceTimelineSegments.at(.init(segments: segments, time: 2)))
        XCTAssertEqual(narrow.range, .init(start: 2, end: 2.02))
        XCTAssertEqual(narrow.classification, .sound)
        XCTAssertEqual(SilenceTimelineSegments.neighbor(.init(
            segments: segments, selection: segments[1].range, direction: .next
        )), narrow)
        XCTAssertEqual(SilenceTimelineSegments.neighbor(.init(
            segments: segments, selection: segments[3].range, direction: .previous
        )), narrow)
        XCTAssertNil(SilenceTimelineSegments.neighbor(.init(
            segments: segments, selection: segments[0].range, direction: .previous
        )))
        XCTAssertNil(SilenceTimelineSegments.neighbor(.init(
            segments: segments, selection: segments[4].range, direction: .next
        )))
        XCTAssertEqual(SilenceTimelineSegments.at(.init(segments: segments, time: 2.02)), segments[3])
        XCTAssertNil(SilenceTimelineSegments.at(.init(segments: segments, time: .nan)))
        XCTAssertNil(SilenceTimelineSegments.at(.init(segments: segments, time: 5)))
    }

    func testNavigationLeavesCustomRangesWithoutReselectingThem() {
        let segments = SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
            .init(start: 2, end: 4, kind: .silence, source: .automatic),
            .init(start: 6, end: 8, kind: .silence, source: .automatic),
        ]))
        let selection = EditorTimeRange(start: 2.5, end: 7)
        XCTAssertEqual(SilenceTimelineSegments.neighbor(.init(
            segments: segments, selection: selection, direction: .previous
        ))?.range, .init(start: 0, end: 2))
        XCTAssertEqual(SilenceTimelineSegments.neighbor(.init(
            segments: segments, selection: selection, direction: .next
        ))?.range, .init(start: 8, end: 10))
    }

    func testClippedAndOverlappingCutsProduceValidSelectableIntervals() {
        let segments = SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
            .init(start: -2, end: 2, kind: .silence, source: .automatic),
            .init(start: 1, end: 3, kind: .silence, source: .automatic),
            .init(start: 8, end: 12, kind: .silence, source: .automatic),
            .init(start: .nan, end: 5, kind: .silence, source: .automatic),
            .init(start: 7, end: 6, kind: .silence, source: .automatic),
        ]))
        XCTAssertEqual(segments.map(\.range.start), [0, 1, 2, 3, 8])
        XCTAssertEqual(segments.map(\.range.end), [1, 2, 3, 8, 10])
        XCTAssertEqual(segments.map(\.classification), [.silence, .silence, .silence, .sound, .silence])
        XCTAssertTrue(SilenceTimelineSegments.resolve(.init(duration: .infinity, cuts: [])).isEmpty)
        XCTAssertTrue(SilenceTimelineSegments.resolve(.init(duration: 0, cuts: [])).isEmpty)
        XCTAssertEqual(SilenceTimelineSegments.resolve(.init(duration: 5, cuts: [])).map(\.range), [.init(start: 0, end: 5)])
    }

    func testVisibleRunsStayBoundedAndPreserveClassificationForAMillionSegments() {
        let duration = 3_240.0
        let count = 1_000_000
        let step = duration / Double(count)
        let segments = (0..<count).map { index in
            SilenceTimelineSegment(
                range: .init(start: Double(index) * step, end: Double(index + 1) * step),
                classification: index.isMultiple(of: 2) ? .sound : .silence
            )
        }
        let viewport = EditorTimelineViewport(lowerBound: 0, upperBound: 1_200)
        let projection = EditorTimelineProjection(.init(duration: duration, cuts: []))
        let started = ContinuousClock.now
        let runs = SilenceTimelineSegments.visibleRuns(
            .init(
                segments: segments,
                projection: projection,
                pixelsPerSecond: 1_200 / duration,
                viewport: viewport,
                selections: [],
                hoveredRange: nil
            ))
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(250))
        XCTAssertFalse(runs.isEmpty)
        XCTAssertLessThanOrEqual(runs.count, 1_200)
        XCTAssertEqual(
            SilenceTimelineSegments.at(.init(segments: segments, time: duration / 2))?.classification,
            count / 2 % 2 == 0 ? .sound : .silence)
        let probe = SilenceTimelineSegments.visibleRuns(
            .init(
                segments: SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
                    .init(start: 2, end: 4, kind: .silence, source: .automatic)
                ])),
                projection: .init(.init(duration: 10, cuts: [])),
                pixelsPerSecond: 100,
                viewport: .init(lowerBound: 0, upperBound: 1_000),
                selections: [],
                hoveredRange: nil
            ))
        XCTAssertEqual(probe.map(\.classification), [.sound, .silence, .sound])
        XCTAssertEqual(probe[0].width, 200, accuracy: 1)
        XCTAssertEqual(probe[1].x, 200, accuracy: 1)
        XCTAssertEqual(probe[1].width, 200, accuracy: 1)
        XCTAssertEqual(probe[1].duration, 2, accuracy: 0.02)
        let selected = SilenceTimelineSegments.visibleRuns(
            .init(
                segments: SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
                    .init(start: 2, end: 4, kind: .silence, source: .automatic)
                ])),
                projection: .init(.init(duration: 10, cuts: [])),
                pixelsPerSecond: 100,
                viewport: .init(lowerBound: 150, upperBound: 350),
                selections: [.init(start: 2, end: 4)],
                hoveredRange: .init(start: 0, end: 2)
            ))
        XCTAssertTrue(selected.contains { $0.classification == .silence && $0.isSelected })
        XCTAssertTrue(SilenceTimelineSegments.contains(.init(start: 2, end: 4), in: [.init(start: 0, end: 2), .init(start: 2, end: 4)]))
        XCTAssertFalse(SilenceTimelineSegments.contains(.init(start: 4, end: 10), in: [.init(start: 2, end: 4)]))
    }

    func testOverlappingUsesBinarySearchBoundsMatchingLinearFilter() {
        let segments = SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
            .init(start: 2, end: 4, kind: .silence, source: .automatic),
            .init(start: 6, end: 8, kind: .silence, source: .automatic),
        ]))
        XCTAssertEqual(
            SilenceTimelineSegments.overlapping(
                .init(segments: segments, start: 2.5, end: 5.5, includesSegmentStartingAtEnd: true)
            ).map(\.range),
            Array(segments[1...2].map(\.range)))
        XCTAssertEqual(
            SilenceTimelineSegments.overlapping(
                .init(segments: segments, start: 4, end: 10, includesSegmentStartingAtEnd: false)
            ).map(\.range),
            Array(segments[2...].map(\.range)))
        XCTAssertTrue(
            SilenceTimelineSegments.overlapping(
                .init(segments: segments, start: .nan, end: 4, includesSegmentStartingAtEnd: true)
            ).isEmpty)
    }

    func testVisibleRunsKeepSelectableSoundBoundariesAndFullDurationWhenScrolling() {
        let segments = SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
            .init(start: 2, end: 4, kind: .silence, source: .user, isEnabled: false)
        ]))
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: []))
        let full = SilenceTimelineSegments.visibleRuns(.init(
            segments: segments, projection: projection, pixelsPerSecond: 100,
            viewport: .init(lowerBound: 0, upperBound: 1_000), selections: [], hoveredRange: nil
        ))
        XCTAssertEqual(full.map(\.duration), [2, 2, 6])
        XCTAssertEqual(full.map(\.x), [0, 200, 400])
        let scrolled = SilenceTimelineSegments.visibleRuns(.init(
            segments: segments, projection: projection, pixelsPerSecond: 100,
            viewport: .init(lowerBound: 500, upperBound: 700), selections: [], hoveredRange: nil
        ))
        XCTAssertEqual(scrolled.count, 1)
        XCTAssertEqual(scrolled.first?.duration, 6)
        XCTAssertEqual(scrolled.first?.width, 200)
    }

    func testSelectionAndNavigationSkipRemovedSegmentsAndRestoreThemAfterUndo() throws {
        let cuts = [
            TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic),
            TimelineCut(start: 6, end: 8, kind: .silence, source: .automatic),
        ]
        let segments = SilenceTimelineSegments.resolve(.init(duration: 10, cuts: cuts))
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: cuts))
        let selectable = SilenceTimelineSegments.selectable(.init(segments: segments, projection: projection))
        XCTAssertEqual(selectable.map(\.range), [segments[0].range, segments[2].range, segments[4].range])
        XCTAssertEqual(SilenceTimelineSegments.neighbor(.init(
            segments: selectable, selection: segments[0].range, direction: .next
        )), segments[2])
        let selection = try XCTUnwrap(SilenceSegmentSelection.dragging(.init(
            current: nil, anchorTime: 1, headTime: 9, segments: selectable, additive: false
        )))
        XCTAssertEqual(selection.ranges, selectable.map(\.range))
        XCTAssertEqual(SilenceTimelineSegments.selectable(.init(
            segments: segments, projection: .init(.init(duration: 10, cuts: []))
        )), segments)
        XCTAssertTrue(SilenceTimelineSegments.selectable(.init(
            segments: segments, projection: .init(.init(duration: 10, cuts: [
                .init(start: 0, end: 10, kind: .manual, source: .user)
            ]))
        )).isEmpty)
    }

    func testSelectableSegmentsMatchProjectionWithThousandsOfCuts() {
        let cuts = (0..<10_000).map { index in
            TimelineCut(start: Double(index) * 0.36 + 0.1, end: Double(index) * 0.36 + 0.2,
                        kind: .silence, source: .automatic)
        }
        let segments = SilenceTimelineSegments.resolve(.init(duration: 3_600, cuts: cuts))
        let projection = EditorTimelineProjection(.init(duration: 3_600, cuts: cuts))
        let actual = SilenceTimelineSegments.selectable(.init(segments: segments, projection: projection))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(3_600), cuts: cuts)
        let expected = segments.filter {
            map.outputSeconds(forTakeSeconds: $0.range.end) > map.outputSeconds(forTakeSeconds: $0.range.start)
        }
        XCTAssertEqual(actual.count, 10_001)
        XCTAssertTrue(actual == expected)
    }

    func testDenseTimelineRenderingBenchmark() throws {
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_EDITOR_BENCHMARK"] == "1" else {
            throw XCTSkip("Set BLITZRECORDER_EDITOR_BENCHMARK=1 to measure timeline rendering")
        }
        let cuts = (0..<10_000).map { index in
            TimelineCut(start: Double(index) * 0.36 + 0.1, end: Double(index) * 0.36 + 0.2,
                        kind: .silence, source: .automatic)
        }
        let segments = SilenceTimelineSegments.resolve(.init(duration: 3_600, cuts: cuts))
        let projection = EditorTimelineProjection(.init(duration: 3_600, cuts: []))
        var timings: [Double] = []
        for index in 0..<31 {
            let started = CFAbsoluteTimeGetCurrent()
            let runs = SilenceTimelineSegments.visibleRuns(.init(
                segments: segments, projection: projection, pixelsPerSecond: 1.0 / 3,
                viewport: .init(lowerBound: 0, upperBound: 1_200),
                selections: segments.filter { $0.classification == .silence }.map(\.range),
                hoveredRange: segments[index].range, pixelScale: 2
            ))
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            XCTAssertLessThanOrEqual(runs.count, 2_400)
            if index > 0 { timings.append(elapsed) }
        }
        timings.sort()
        print("Dense timeline: 3,600 seconds, 10,000 cuts, Retina; median \(timings[15]) ms, p95 \(timings[28]) ms")
        XCTAssertLessThan(timings[15], 50)
    }
}
