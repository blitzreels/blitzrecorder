import XCTest
@testable import BlitzRecorderApp

final class EditorTranscriptTimelineTests: XCTestCase {
    private func transcript() -> RecordingTranscript {
        RecordingTranscriptAssembler.assemble(.init(
            mediaPath: "/recording", generatedAt: Date(timeIntervalSince1970: 0), duration: 10,
            confidence: 0.95, text: "hello hello", suggestedTitle: nil,
            words: [
                .init(text: "hello", startTime: 1, endTime: 1.4, confidence: 0.95),
                .init(text: "hello", startTime: 1.7, endTime: 2.1, confidence: 0.95)
            ],
            diarizedIntervals: [.init(speakerID: "speaker", startTime: 0.9, endTime: 2.2)]
        ))
    }

    func testWordTimingsAndSpeechRangesSurviveSavingAndSpeakerMerge() throws {
        let original = transcript()
        let decoded = try JSONDecoder().decode(RecordingTranscript.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.words, original.words)
        XCTAssertEqual(decoded.speechRanges, original.speechRanges)
        let items = EditorTranscriptTimeline.items(.init(transcript: decoded, windows: [], threshold: -42, duration: 10))
        XCTAssertEqual(items.map(\.text), ["hello", "hello"])
        XCTAssertEqual(items.map(\.range), [.init(start: 1, end: 1.4), .init(start: 1.7, end: 2.1)])
        XCTAssertNotEqual(items[0].id, items[1].id)
    }

    func testLoudNonDialogueIsMarkedWithoutMarkingSpeechOrQuietGaps() {
        let items = EditorTranscriptTimeline.items(.init(
            transcript: transcript(), windows: [
                .init(start: 1.4, end: 1.6, decibels: -15),
                .init(start: 4, end: 4.2, decibels: -10),
                .init(start: 6, end: 7, decibels: -80)
            ], threshold: -42, duration: 10
        ))
        let sounds = items.filter { $0.kind == .nonDialogue }
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(sounds.first?.range.start ?? 0, 3.94, accuracy: 0.001)
        XCTAssertEqual(sounds.first?.range.end ?? 0, 4.26, accuracy: 0.001)
    }

    func testLoudAudioWithoutWordsIsNonDialogueEvenInsideACoarseSpeechRange() {
        var wide = transcript()
        wide.speechRanges = [.init(startTime: 0, endTime: 10)]
        let items = EditorTranscriptTimeline.items(.init(
            transcript: wide, windows: [
                .init(start: 1, end: 2.2, decibels: -12),
                .init(start: 4, end: 7, decibels: -8)
            ], threshold: -42, duration: 10
        ))
        let sounds = items.filter { $0.kind == .nonDialogue }
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(sounds.first?.range.start ?? 0, 3.94, accuracy: 0.001)
        XCTAssertEqual(sounds.first?.range.end ?? 0, 7.06, accuracy: 0.001)
        XCTAssertTrue(items.contains { $0.kind == .word && $0.text == "hello" })
    }

    func testTenWordShiftSelectionKeepsAnchorAndCommandSelectionKeepsGaps() throws {
        let items = (0..<10).map { EditorTranscriptItem(id: $0,
            range: .init(start: Double($0), end: Double($0) + 0.8), text: "word", kind: .word) }
        let first = EditorSelection.range(items[0].range)
        let selected = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: first.rangeSelection, target: items[9].range, ranges: items.map(\.range),
            extending: true, toggling: false)))
        XCTAssertEqual(selected.ranges, items.map(\.range))
        let shorter = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: EditorSelection.ranges(selected).rangeSelection, target: items[4].range,
            ranges: items.map(\.range), extending: true, toggling: false)))
        XCTAssertEqual(shorter.ranges, Array(items.prefix(5).map(\.range)))
        XCTAssertEqual(shorter.anchor, items[0].range)
        let disjoint = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: first.rangeSelection, target: items[9].range, ranges: items.map(\.range),
            extending: false, toggling: true)))
        let edits = try XCTUnwrap(EditorTimeRange.removingTogether(.init(
            ranges: disjoint.ranges, kind: .manual, edits: .empty, takeDuration: 10)))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: edits.cuts)
        XCTAssertTrue(map.isRemoved(takeTime: 0.5))
        XCTAssertTrue(map.isRemoved(takeTime: 9.5))
        XCTAssertFalse(map.isRemoved(takeTime: 4.5))
        XCTAssertEqual(map.removedDuration, 1.6, accuracy: 0.002)
    }

    func testRemovedSilenceDoesNotReappearFromSubframeRounding() {
        let cuts = [TimelineCut(start: 4.940000000000001, end: 5.260000000000001, kind: .silence, source: .user)]
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: cuts))
        XCTAssertTrue(EditorTranscriptTimeline.remainingSilence(.init(cuts: cuts, projection: projection)).isEmpty)
        XCTAssertEqual(EditorTranscriptTimeline.remainingSilence(.init(cuts: cuts,
            projection: .init(.init(duration: 10, cuts: [])))), cuts)
    }

    func testAdjacentASRWordsRemainTenDistinctToggleableItems() throws {
        let starts = [1.36, 1.92, 2.24, 2.48, 2.72, 2.88, 3.04, 3.2, 3.52, 3.7600000000000002]
        let ends = [1.92, 2.2399999999999998, 2.4800000000000004, 2.64, 2.8800000000000003,
                    3.04, 3.2, 3.52, 3.76, 3.9200000000000004]
        let ranges = zip(starts, ends).map { EditorTimeRange(start: $0, end: $1) }
        let selection = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: .init(ranges[0]), target: ranges[9], ranges: ranges, extending: true, toggling: false)))
        XCTAssertEqual(selection.ranges, ranges)
        let toggled = try XCTUnwrap(SilenceSegmentSelection.clickingItems(.init(
            current: selection, target: ranges[4], ranges: ranges, extending: false, toggling: true)))
        XCTAssertEqual(toggled.ranges.count, 9)
        XCTAssertFalse(toggled.ranges.contains(ranges[4]))
    }

    func testZoomedOutTranscriptWorkIsBoundedByViewportAndHitTestingKeepsExactWords() {
        let items = (0..<100_000).map { EditorTranscriptItem(id: $0,
            range: .init(start: Double($0) * 0.1, end: Double($0) * 0.1 + 0.08), text: "word", kind: .word) }
        let layout = EditorTranscriptLayout(.init(items: items, projection: .init(.init(duration: 10_000, cuts: []))))
        let start = ContinuousClock.now
        for zoom in [1.0, 4, 16, 64, 256, 1024] {
            let runs = layout.runs(.init(viewport: .init(lowerBound: 0, upperBound: 1000), pixelsPerSecond: 0.1 * zoom))
            XCTAssertLessThanOrEqual(runs.count, 1000)
            XCTAssertLessThanOrEqual(runs.filter { $0.width >= 28 }.count, 36)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(0.5))
        XCTAssertEqual(layout.item(at: 742.53)?.source.id, 7425)
        XCTAssertNil(layout.item(at: 742.59))
    }

    func testTranscriptLayoutProjectsSavedCutsAndClipsToScrolledViewport() {
        let items = (0..<10).map { EditorTranscriptItem(id: $0,
            range: .init(start: Double($0), end: Double($0) + 0.8), text: "word", kind: .word) }
        let layout = EditorTranscriptLayout(.init(items: items, projection: .init(.init(duration: 10,
            cuts: [.init(start: 2, end: 5, kind: .manual, source: .user)]))))
        XCTAssertEqual(layout.items.map { $0.source.id }, [0, 1, 5, 6, 7, 8, 9])
        XCTAssertEqual(layout.item(at: 2.1)?.source.id, 5)
        let runs = layout.runs(.init(viewport: .init(lowerBound: 225, upperBound: 500), pixelsPerSecond: 100))
        XCTAssertEqual(runs.first?.item.source.id, 5)
        XCTAssertEqual(runs.first?.x, 0)
        XCTAssertTrue(runs.allSatisfy { $0.x >= 0 && $0.x + $0.width <= 275 })
    }

    func testLegacyTranscriptShowsPhrasesWithoutInventingWordTimestamps() throws {
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(transcript())) as? [String: Any])
        payload.removeValue(forKey: "words")
        payload.removeValue(forKey: "speechRanges")
        let old = try JSONDecoder().decode(RecordingTranscript.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(old.words)
        let items = EditorTranscriptTimeline.items(.init(transcript: old, windows: [], threshold: -42, duration: 10))
        XCTAssertEqual(items.count, old.segments.count)
        XCTAssertTrue(items.allSatisfy { $0.kind == .phrase })
    }

    func testWordDeletionUsesExactTimelineRangeAndPreservesOtherWord() throws {
        let items = EditorTranscriptTimeline.items(.init(transcript: transcript(), windows: [], threshold: -42, duration: 10))
        let edited = try XCTUnwrap(EditorTimeRange.removing(.init(range: items[0].range, edits: .empty, takeDuration: 10)))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: edited.cuts)
        XCTAssertTrue(map.isRemoved(takeTime: 1.2))
        XCTAssertFalse(map.isRemoved(takeTime: 1.9))
        XCTAssertEqual(map.removedDuration, 0.4, accuracy: 0.002)
    }
}
