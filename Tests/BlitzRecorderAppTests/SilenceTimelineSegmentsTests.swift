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
}
