import XCTest

@testable import BlitzRecorderApp

final class EditorTimelineProjectionTests: XCTestCase {
    func testRemovedSilenceClosesGapsAndSeeksToNextKeptFrame() {
        let cuts = [
            TimelineCut(start: 0, end: 1, kind: .silence, source: .automatic),
            TimelineCut(start: 3, end: 5, kind: .silence, source: .automatic),
            TimelineCut(start: 9, end: 10, kind: .silence, source: .automatic),
        ]
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: cuts))
        XCTAssertEqual(projection.duration, 6)
        XCTAssertEqual(projection.takeTime(0), 1)
        XCTAssertEqual(projection.takeTime(2), 5)
        XCTAssertEqual(projection.takeTime(6), 9)
        XCTAssertEqual(projection.displayTime(4), 2)
        XCTAssertEqual(projection.displayTime(7), 4)
        let fragments = projection.visibleFragments(.init(start: 1, end: 3))
        XCTAssertEqual(
            fragments,
            [
                .init(takeStart: 2, takeEnd: 3, start: 1),
                .init(takeStart: 5, takeEnd: 6, start: 2),
            ])
    }

    func testMappedWaveformDoesNotIncludeDeletedPeaks() {
        let waveform = EditorAudioWaveform(.init(peaks: [0.2, 0.2, 1, 1, 0.4, 0.4]))
        let projection = EditorTimelineProjection(
            .init(
                duration: 6,
                cuts: [
                    TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic)
                ]))
        let peaks = projection.visibleFragments(.init(start: 1, end: 3)).map {
            waveform.amplitude(.init(start: $0.takeStart / 6, end: $0.takeEnd / 6))
        }
        XCTAssertEqual(peaks, [0.2, 0.4])
        let bands = SilenceTimelineBands.visible(
            .init(
                cuts: [.init(start: 2, end: 4, kind: .silence, source: .automatic)],
                projection: projection, pixelsPerSecond: 100, viewport: .init(lowerBound: 0, upperBound: 400)
            ))
        XCTAssertTrue(bands.isEmpty)
    }

    func testProjectionMatchesPlaybackMapWithHundredsOfCuts() {
        let cuts = (0..<181).map {
            TimelineCut(
                start: Double($0) * 10 + 2, end: Double($0) * 10 + 2.576,
                kind: .silence, source: .automatic)
        }
        let projection = EditorTimelineProjection(.init(duration: 1_978, cuts: cuts))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(1_978), cuts: cuts)
        XCTAssertEqual(projection.duration, map.outputDuration.seconds)
        for time in stride(from: 0.0, through: projection.duration, by: 0.37) {
            XCTAssertEqual(projection.takeTime(time), map.takeSeconds(forOutputSeconds: time), accuracy: 0.002)
            XCTAssertEqual(projection.displayTime(projection.takeTime(time)), time, accuracy: 0.002)
        }
        let restored = EditorTimelineProjection(.init(duration: 1_978, cuts: []))
        XCTAssertEqual(restored.duration, 1_978)
        XCTAssertEqual(restored.takeTime(600), 600)
    }
}
