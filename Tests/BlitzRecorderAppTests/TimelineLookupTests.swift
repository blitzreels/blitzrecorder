import CoreMedia
import XCTest
@testable import BlitzRecorderApp

final class TimelineLookupTests: XCTestCase {
    func testLookupsMatchLinearReferenceAcrossCutsAndSeams() {
        let cuts: [TimelineCut] = (0..<80).map { index in
            let start = Double((index * 37) % 200) / 10
            let duration = 0.05 + Double(index % 5) / 10
            return .init(start: start, end: start + duration,
                         kind: .silence, source: .automatic, isEnabled: !index.isMultiple(of: 7))
        }
        for map in [
            TimelineTimeMap(takeDuration: TimelineTimeMap.time(22), cuts: cuts),
            TimelineTimeMap.identity(takeDuration: TimelineTimeMap.time(22)),
            TimelineTimeMap(takeDuration: TimelineTimeMap.time(22), cuts: [
                .init(start: 0, end: 22, kind: .manual, source: .user)
            ]),
            TimelineTimeMap.identity(takeDuration: .zero)
        ] {
            let boundaries = map.removedRanges.flatMap { [$0.start, $0.end] }
                + map.keptRanges.flatMap { [$0.outputStart.seconds, $0.outputEnd.seconds] }
            let probes = boundaries.flatMap { [$0 - 1.0 / 600, $0, $0 + 1.0 / 600] }
                + stride(from: -1.0, through: 23.0, by: 0.073).map { $0 }
            for seconds in probes {
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                let takeRange = map.keptRanges.first { CMTimeCompare(time, $0.takeEnd) < 0 }
                let expectedOutput = takeRange.map {
                    CMTimeCompare(time, $0.takeStart) < 0 ? $0.outputStart
                        : CMTimeAdd($0.outputStart, CMTimeSubtract(time, $0.takeStart))
                } ?? map.outputDuration
                XCTAssertEqual(CMTimeCompare(map.outputTime(forTake: time), expectedOutput), 0)

                let outputRange = map.keptRanges.first { CMTimeCompare(time, $0.outputEnd) < 0 }
                let expectedTake = outputRange.map {
                    CMTimeAdd($0.takeStart, CMTimeMaximum(.zero, CMTimeSubtract(time, $0.outputStart)))
                } ?? map.keptRanges.last?.takeEnd ?? map.takeDuration
                XCTAssertEqual(CMTimeCompare(map.takeTime(forOutput: time), expectedTake), 0)
                XCTAssertEqual(map.removedRange(containing: seconds),
                    map.removedRanges.first { seconds >= $0.start && seconds < $0.end })
                XCTAssertEqual(map.keptRange(containingOutput: time), map.keptRanges.first {
                    CMTimeCompare(time, $0.outputStart) >= 0 && CMTimeCompare(time, $0.outputEnd) < 0
                })
            }
            XCTAssertNil(map.removedRange(containing: .nan))
            XCTAssertNil(map.removedRange(containing: .infinity))
            XCTAssertNil(map.removedRange(containing: -.infinity))
        }
    }
}
