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
            if let last = distinct.last, range.start < last.end {
                distinct[distinct.count - 1] = .init(start: last.start, end: max(last.end, range.end))
            } else if distinct.last != range {
                distinct.append(range)
            }
        }
        guard !distinct.isEmpty else { return nil }
        self.ranges = distinct
        self.anchor = contents.anchor
    }

    var bounds: EditorTimeRange {
        .init(start: ranges[0].start, end: ranges[ranges.count - 1].end)
    }

    var duration: Double { ranges.reduce(0) { $0 + $1.duration } }

    struct Click {
        let current: SilenceSegmentSelection?
        let target: EditorTimeRange
        let segments: [SilenceTimelineSegment]
        let extending: Bool
        let toggling: Bool
    }

    static func clicking(_ request: Click) -> Self? {
        if request.extending, let current = request.current {
            let start = min(current.anchor.start, request.target.start)
            let end = max(current.anchor.end, request.target.end)
            let extensionRanges = request.segments.map(\.range).filter { $0.start < end && $0.end > start }
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
        let ranges = request.segments.map(\.range).filter { $0.start <= end && $0.end > start }
        guard let anchor = SilenceTimelineSegments.at(.init(
            segments: request.segments, time: request.anchorTime
        ))?.range ?? ranges.first else { return nil }
        return Self(.init(ranges: (request.additive ? request.current?.ranges ?? [] : []) + ranges, anchor: anchor))
    }
}
