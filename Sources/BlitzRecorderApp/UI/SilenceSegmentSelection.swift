import Foundation

struct SilenceSegmentSelection: Equatable {
    let ranges: [EditorTimeRange]
    let anchor: EditorTimeRange

    init(_ range: EditorTimeRange) {
        ranges = [range]
        anchor = range
    }

    private struct Contents {
        let ranges: [EditorTimeRange]
        let anchor: EditorTimeRange
    }

    private init?(_ contents: Contents) {
        let ordered = contents.ranges.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var distinct: [EditorTimeRange] = []
        for range in ordered {
            if distinct.last != range {
                distinct.append(range)
            }
        }
        guard !distinct.isEmpty else { return nil }
        self.ranges = distinct
        self.anchor = contents.anchor
    }

    var bounds: EditorTimeRange {
        .init(start: ranges[0].start, end: ranges.reduce(ranges[0].end) { max($0, $1.end) })
    }

    var duration: Double { displayRanges.reduce(0) { $0 + $1.duration } }

    var displayRanges: [EditorTimeRange] {
        Self.coalesced(ranges)
    }

    static func coalesced(_ ranges: [EditorTimeRange]) -> [EditorTimeRange] {
        guard var current = ranges.first else { return [] }
        var merged: [EditorTimeRange] = []
        for range in ranges.dropFirst() {
            if range.start <= current.end + 1.0 / 600 {
                current = .init(start: current.start, end: max(current.end, range.end))
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    struct Click {
        let current: SilenceSegmentSelection?
        let target: EditorTimeRange
        let segments: [SilenceTimelineSegment]
        let extending: Bool
        let toggling: Bool
    }

    static func clicking(_ request: Click) -> Self? {
        let ranges: [EditorTimeRange]
        if request.extending, let current = request.current {
            ranges = SilenceTimelineSegments.overlapping(.init(segments: request.segments,
                start: min(current.anchor.start, request.target.start), end: max(current.anchor.end, request.target.end),
                includesSegmentStartingAtEnd: false)).map(\.range)
        } else {
            ranges = []
        }
        return clickingItems(.init(current: request.current, target: request.target,
            ranges: ranges, extending: request.extending, toggling: request.toggling))
    }

    struct ItemClick {
        let current: SilenceSegmentSelection?
        let target: EditorTimeRange
        let ranges: [EditorTimeRange]
        let extending: Bool
        let toggling: Bool
    }

    static func clickingItems(_ request: ItemClick) -> Self? {
        if request.extending, let current = request.current {
            let start = min(current.anchor.start, request.target.start)
            let end = max(current.anchor.end, request.target.end)
            let extensionRanges: [EditorTimeRange]
            if let anchorIndex = request.ranges.firstIndex(of: current.anchor),
                let targetIndex = request.ranges.firstIndex(of: request.target) {
                extensionRanges = Array(request.ranges[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)])
            } else {
                extensionRanges = request.ranges.filter { $0.start < end - 1e-9 && $0.end > start + 1e-9 }
            }
            return Self(.init(
                ranges: (request.toggling ? current.ranges : []) + extensionRanges,
                anchor: current.anchor
            ))
        }
        if request.toggling, let current = request.current {
            let ranges = current.ranges.contains(request.target)
                ? current.ranges.filter { $0 != request.target }
                : current.ranges + [request.target]
            return Self(.init(ranges: ranges, anchor: request.target))
        }
        return Self(request.target)
    }

    struct Drag {
        let current: SilenceSegmentSelection?
        let anchorTime: Double
        let headTime: Double
        let segments: [SilenceTimelineSegment]
        let additive: Bool
    }

    static func dragging(_ request: Drag) -> Self? {
        let start = min(request.anchorTime, request.headTime)
        let end = max(request.anchorTime, request.headTime)
        let ranges = SilenceTimelineSegments.overlapping(
            .init(
                segments: request.segments, start: start, end: end, includesSegmentStartingAtEnd: true
            )
        ).map(\.range)
        guard let anchor = SilenceTimelineSegments.at(.init(
            segments: request.segments, time: request.anchorTime
        ))?.range ?? ranges.first else { return nil }
        return Self(.init(ranges: (request.additive ? request.current?.ranges ?? [] : []) + ranges, anchor: anchor))
    }
}
