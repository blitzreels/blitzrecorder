import Foundation

struct EditorTimelineProjection: Equatable {
    struct Request: Equatable {
        let duration: Double
        let cuts: [TimelineCut]
    }

    struct RangeRequest {
        let start: Double
        let end: Double
    }

    struct Fragment: Equatable, Identifiable {
        let takeStart: Double
        let takeEnd: Double
        let start: Double

        var id: Double { start }
        var duration: Double { takeEnd - takeStart }
        var end: Double { start + duration }
    }

    let fragments: [Fragment]
    let duration: Double

    init(_ request: Request) {
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(request.duration), cuts: request.cuts)
        fragments = map.keptRanges.map {
            Fragment(takeStart: $0.takeStart.seconds, takeEnd: $0.takeEnd.seconds, start: $0.outputStart.seconds)
        }
        duration = map.outputDuration.seconds
    }

    func displayTime(_ takeTime: Double) -> Double {
        let index = firstIndex { $0.takeEnd > takeTime }
        guard index < fragments.count else { return duration }
        let fragment = fragments[index]
        return fragment.start + max(0, takeTime - fragment.takeStart)
    }

    func takeTime(_ displayTime: Double) -> Double {
        let index = firstIndex { $0.end > displayTime }
        guard index < fragments.count else { return fragments.last?.takeEnd ?? 0 }
        let fragment = fragments[index]
        return fragment.takeStart + max(0, displayTime - fragment.start)
    }

    func visibleFragments(_ request: RangeRequest) -> [Fragment] {
        guard request.end > request.start else { return [] }
        let first = firstIndex { $0.end > request.start }
        var result: [Fragment] = []
        for fragment in fragments.dropFirst(first) {
            guard fragment.start < request.end else { break }
            let start = max(request.start, fragment.start)
            let end = min(request.end, fragment.end)
            result.append(
                Fragment(
                    takeStart: fragment.takeStart + start - fragment.start,
                    takeEnd: fragment.takeStart + end - fragment.start,
                    start: start
                ))
        }
        return result
    }

    private func firstIndex(_ predicate: (Fragment) -> Bool) -> Int {
        var lower = 0
        var upper = fragments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(fragments[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}
