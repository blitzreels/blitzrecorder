import Foundation
import XCTest
@testable import BlitzRecorderDomain

final class TimelineTimeMapTests: XCTestCase {
    func testOverlappingCutsMergeAndSeamSeeksToNextKeptSample() {
        let map = TimelineTimeMap(takeDuration: MediaTime(seconds: 10), cuts: [
            .init(start: 2, end: 4, kind: .manual, source: .user),
            .init(start: 3, end: 5, kind: .silence, source: .automatic),
            .init(start: 8, end: 9, kind: .manual, source: .user, isEnabled: false)
        ])
        XCTAssertEqual(map.outputDuration.seconds, 7, accuracy: 0.001)
        XCTAssertEqual(map.outputSeconds(forTakeSeconds: 3), 2, accuracy: 0.001)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 2), 5, accuracy: 0.001)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 1.99), 1.99, accuracy: 0.002)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 6), 9, accuracy: 0.001)
    }

    func testOffsetAudioUsesTheSameKeptRangesAsVideo() {
        let map = TimelineTimeMap(takeDuration: MediaTime(seconds: 5), cuts: [
            .init(start: 1, end: 2, kind: .manual, source: .user)
        ])
        let pieces = map.mediaInsertions(.init(
            activeTakeStart: MediaTime(seconds: 0.5),
            sourceTimeAtActiveStart: MediaTime(seconds: 0.2),
            sourceEnd: MediaTime(seconds: 4.7)
        ))
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].compositionStart.seconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(pieces[0].sourceStart.seconds, 0.2, accuracy: 0.001)
        XCTAssertEqual(pieces[1].compositionStart.seconds, 1, accuracy: 0.001)
        XCTAssertEqual(pieces[1].sourceStart.seconds, 1.7, accuracy: 0.001)
    }

    func testLookupsMatchLinearReferenceAcrossCutsAndSeams() {
        let cuts: [TimelineCut] = (0..<80).map { index in
            let start = Double((index * 37) % 200) / 10
            let duration = 0.05 + Double(index % 5) / 10
            return .init(
                start: start,
                end: start + duration,
                kind: .silence,
                source: .automatic,
                isEnabled: !index.isMultiple(of: 7)
            )
        }
        for map in [
            TimelineTimeMap(takeDuration: MediaTime(seconds: 22), cuts: cuts),
            TimelineTimeMap.identity(takeDuration: MediaTime(seconds: 22)),
            TimelineTimeMap(takeDuration: MediaTime(seconds: 22), cuts: [
                .init(start: 0, end: 22, kind: .manual, source: .user)
            ]),
            TimelineTimeMap.identity(takeDuration: .zero)
        ] {
            let boundaries = map.removedRanges.flatMap { [$0.start, $0.end] }
                + map.keptRanges.flatMap { [$0.outputStart.seconds, $0.outputEnd.seconds] }
            let probes = boundaries.flatMap { [$0 - 1.0 / 600, $0, $0 + 1.0 / 600] }
                + stride(from: -1.0, through: 23.0, by: 0.073).map { $0 }
            for seconds in probes {
                let time = MediaTime(seconds: seconds)
                let takeRange = map.keptRanges.first { time < $0.takeEnd }
                let expectedOutput = takeRange.map {
                    time < $0.takeStart ? $0.outputStart : $0.outputStart + (time - $0.takeStart)
                } ?? map.outputDuration
                XCTAssertEqual(map.outputTime(forTake: time), expectedOutput)

                let outputRange = map.keptRanges.first { time < $0.outputEnd }
                let expectedTake = outputRange.map {
                    $0.takeStart + MediaTime.maximum(.zero, time - $0.outputStart)
                } ?? map.keptRanges.last?.takeEnd ?? map.takeDuration
                XCTAssertEqual(map.takeTime(forOutput: time), expectedTake)
                XCTAssertEqual(
                    map.removedRange(containing: seconds),
                    map.removedRanges.first { seconds >= $0.start && seconds < $0.end }
                )
                XCTAssertEqual(map.keptRange(containingOutput: time), map.keptRanges.first {
                    time >= $0.outputStart && time < $0.outputEnd
                })
            }
            XCTAssertNil(map.removedRange(containing: .nan))
            XCTAssertNil(map.removedRange(containing: .infinity))
            XCTAssertNil(map.removedRange(containing: -.infinity))
        }
    }

    func testPlaybackRateShortensOutputAndKeepsSourceDuration() {
        XCTAssertEqual(TimelineTimeMap.clampedRateTenths(1.15), 12)
        XCTAssertEqual(TimelineTimeMap.clampedRateTenths(0.5), 10)
        XCTAssertEqual(TimelineTimeMap.clampedRateTenths(3), 20)

        let map = TimelineTimeMap(
            takeDuration: MediaTime(seconds: 10),
            cuts: [.init(start: 2, end: 4, kind: .manual, source: .user)],
            playbackRate: 2
        )
        XCTAssertEqual(map.playbackRate, 2, accuracy: 0.0001)
        XCTAssertEqual(map.outputDuration.seconds, 4, accuracy: 0.001)
        XCTAssertEqual(map.outputSeconds(forTakeSeconds: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(map.takeSeconds(forOutputSeconds: 1), 4, accuracy: 0.001)

        let pieces = map.mediaInsertions(.init(
            activeTakeStart: .zero,
            sourceTimeAtActiveStart: .zero,
            sourceEnd: MediaTime(seconds: 10)
        ))
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].sourceDuration.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(pieces[0].duration.seconds, 1, accuracy: 0.001)
        XCTAssertEqual(pieces[0].compositionStart.seconds, 0, accuracy: 0.001)
        XCTAssertEqual(pieces[1].sourceStart.seconds, 4, accuracy: 0.001)
        XCTAssertEqual(pieces[1].sourceDuration.seconds, 6, accuracy: 0.001)
        XCTAssertEqual(pieces[1].duration.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(pieces[1].compositionStart.seconds, 1, accuracy: 0.001)
    }
}
