import XCTest

@testable import BlitzRecorderApp

final class SilenceSegmentSelectionTests: XCTestCase {
    private var segments: [SilenceTimelineSegment] {
        SilenceTimelineSegments.resolve(.init(duration: 10, cuts: [
            .init(start: 2, end: 4, kind: .silence, source: .automatic),
            .init(start: 6, end: 8, kind: .silence, source: .automatic),
        ]))
    }

    func testCommandClickTogglesDisjointSegmentsWithoutSelectingTheGap() throws {
        let first = SilenceSegmentSelection(segments[0].range)
        let added = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: first, target: segments[4].range, segments: segments, extending: false, toggling: true
        )))
        XCTAssertEqual(added.ranges, [segments[0].range, segments[4].range])
        XCTAssertEqual(added.duration, 4)
        XCTAssertEqual(added.bounds, .init(start: 0, end: 10))
        XCTAssertNil(EditorSelection.silenceRanges(added).timeRange)
        let removed = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: added, target: segments[0].range, segments: segments, extending: false, toggling: true
        )))
        XCTAssertEqual(removed.ranges, [segments[4].range])
        XCTAssertEqual(EditorSelection.silenceRanges(removed).timeRange, segments[4].range)
        XCTAssertNil(SilenceSegmentSelection.clicking(.init(
            current: removed, target: segments[4].range, segments: segments, extending: false, toggling: true
        )))
    }

    func testShiftClickKeepsAnchorWhenExtendingAndShrinkingInEitherDirection() throws {
        let first = SilenceSegmentSelection(segments[2].range)
        let right = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: first, target: segments[4].range, segments: segments, extending: true, toggling: false
        )))
        XCTAssertEqual(right.ranges, Array(segments[2...4].map(\.range)))
        let left = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: right, target: segments[0].range, segments: segments, extending: true, toggling: false
        )))
        XCTAssertEqual(left.ranges, Array(segments[0...2].map(\.range)))
        let shrunk = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: left, target: segments[1].range, segments: segments, extending: true, toggling: false
        )))
        XCTAssertEqual(shrunk.ranges, Array(segments[1...2].map(\.range)))
        XCTAssertEqual(shrunk.anchor, segments[2].range)
    }

    func testCommandShiftAddsRangeAndPlainClickReplacesSelection() throws {
        let first = SilenceSegmentSelection(segments[0].range)
        let disjoint = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: first, target: segments[3].range, segments: segments, extending: false, toggling: true
        )))
        let extended = try XCTUnwrap(SilenceSegmentSelection.clicking(.init(
            current: disjoint, target: segments[4].range, segments: segments, extending: true, toggling: true
        )))
        XCTAssertEqual(extended.ranges, [segments[0].range, segments[3].range, segments[4].range])
        let replaced = SilenceSegmentSelection.clicking(.init(
            current: extended, target: segments[2].range, segments: segments, extending: false, toggling: false
        ))
        XCTAssertEqual(replaced, SilenceSegmentSelection(segments[2].range))
    }

    func testDragSelectsWholeSegmentsInEitherDirectionAndCanAddToSelection() throws {
        let forward = try XCTUnwrap(SilenceSegmentSelection.dragging(.init(
            current: nil, anchorTime: 2.5, headTime: 5.5, segments: segments, additive: false
        )))
        let backward = try XCTUnwrap(SilenceSegmentSelection.dragging(.init(
            current: nil, anchorTime: 5.5, headTime: 2.5, segments: segments, additive: false
        )))
        XCTAssertEqual(forward.ranges, Array(segments[1...2].map(\.range)))
        XCTAssertEqual(backward.ranges, forward.ranges)
        XCTAssertEqual(forward.anchor, segments[1].range)
        XCTAssertEqual(backward.anchor, segments[2].range)
        let additive = try XCTUnwrap(SilenceSegmentSelection.dragging(.init(
            current: forward, anchorTime: 8.5, headTime: 9, segments: segments, additive: true
        )))
        XCTAssertEqual(additive.ranges, [segments[1].range, segments[2].range, segments[4].range])
        let shrunk = try XCTUnwrap(SilenceSegmentSelection.dragging(.init(
            current: forward, anchorTime: 8.5, headTime: 7.5, segments: segments, additive: false
        )))
        XCTAssertEqual(shrunk.ranges, Array(segments[3...4].map(\.range)))
    }
}
