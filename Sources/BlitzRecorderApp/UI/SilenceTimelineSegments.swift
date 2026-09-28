import SwiftUI

struct SilenceTimelineSegment: Equatable, Identifiable {
    let range: EditorTimeRange
    let classification: SilenceClassification

    var id: Double { range.start }
    var title: String { classification == .silence ? "Silence" : "Sound" }
    var symbol: String { classification == .silence ? "waveform.slash" : "waveform" }
}

enum SilenceTimelineSegments {
    struct Request: Equatable {
        let duration: Double
        let cuts: [TimelineCut]
    }

    struct Lookup {
        let segments: [SilenceTimelineSegment]
        let time: Double
    }

    enum Direction {
        case previous
        case next
    }

    struct Navigation {
        let segments: [SilenceTimelineSegment]
        let selection: EditorTimeRange
        let direction: Direction
    }

    struct OverlapRequest {
        let segments: [SilenceTimelineSegment]
        let start: Double
        let end: Double
        let includesSegmentStartingAtEnd: Bool
    }

    struct SelectableRequest: Equatable {
        let segments: [SilenceTimelineSegment]
        let projection: EditorTimelineProjection
    }

    struct VisibleRequest {
        let segments: [SilenceTimelineSegment]
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let viewport: EditorTimelineViewport
        let selections: [EditorTimeRange]
        let hoveredRange: EditorTimeRange?
        var pixelScale: CGFloat = 1
    }

    struct VisibleRun: Equatable {
        let x: CGFloat
        let width: CGFloat
        let duration: Double
        let classification: SilenceClassification
        let isSelected: Bool
        let isHovered: Bool
    }

    static func resolve(_ request: Request) -> [SilenceTimelineSegment] {
        guard request.duration.isFinite, request.duration > 0 else { return [] }
        let cuts = request.cuts.filter {
            $0.kind == .silence && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
                && $0.end > 0 && $0.start < request.duration
        }
        var boundaries: Set<Double> = [0, request.duration]
        var changes: [Double: Int] = [:]
        for cut in cuts {
            let start = max(0, cut.start)
            let end = min(request.duration, cut.end)
            boundaries.insert(start)
            boundaries.insert(end)
            if cut.isEnabled {
                changes[start, default: 0] += 1
                changes[end, default: 0] -= 1
            }
        }
        let ordered = boundaries.sorted()
        var activeSilence = 0
        return zip(ordered, ordered.dropFirst()).map { interval in
            activeSilence += changes[interval.0, default: 0]
            let range = EditorTimeRange(start: interval.0, end: interval.1)
            return SilenceTimelineSegment(
                range: range, classification: activeSilence > 0 ? .silence : .sound
            )
        }
    }

    struct CapRequest {
        let segments: [SilenceTimelineSegment]
        let end: Double
    }

    static func capped(_ request: CapRequest) -> [SilenceTimelineSegment] {
        guard request.end.isFinite, request.end > 0 else { return [] }
        return request.segments.compactMap { segment in
            guard segment.range.start < request.end else { return nil }
            if segment.range.end <= request.end { return segment }
            return SilenceTimelineSegment(
                range: EditorTimeRange(start: segment.range.start, end: request.end),
                classification: segment.classification
            )
        }
    }

    static func at(_ request: Lookup) -> SilenceTimelineSegment? {
        guard request.time.isFinite, !request.segments.isEmpty else { return nil }
        let index = firstIndex(in: request.segments) { $0.range.start > request.time } - 1
        guard request.segments.indices.contains(index) else { return nil }
        let segment = request.segments[index]
        return request.time < segment.range.end ? segment : nil
    }

    static func selectable(_ request: SelectableRequest) -> [SilenceTimelineSegment] {
        var fragmentIndex = 0
        let fragments = request.projection.fragments
        return request.segments.filter { segment in
            let start = TimelineTimeMap.time(segment.range.start).seconds
            let end = TimelineTimeMap.time(segment.range.end).seconds
            guard end > start else { return false }
            while fragmentIndex < fragments.count, fragments[fragmentIndex].takeEnd <= start {
                fragmentIndex += 1
            }
            return fragmentIndex < fragments.count && fragments[fragmentIndex].takeStart < end
        }
    }

    static func neighbor(_ request: Navigation) -> SilenceTimelineSegment? {
        switch request.direction {
        case .previous:
            let index = firstIndex(in: request.segments) {
                $0.range.end > request.selection.start + 1.0 / 600
            } - 1
            return request.segments.indices.contains(index) ? request.segments[index] : nil
        case .next:
            let index = firstIndex(in: request.segments) {
                $0.range.start >= request.selection.end - 1.0 / 600
            }
            return request.segments.indices.contains(index) ? request.segments[index] : nil
        }
    }

    static func overlapping(_ request: OverlapRequest) -> ArraySlice<SilenceTimelineSegment> {
        let start = min(request.start, request.end)
        let end = max(request.start, request.end)
        guard start.isFinite, end.isFinite, !request.segments.isEmpty else { return [] }
        let first = firstIndex(in: request.segments) { $0.range.end > start }
        let last = firstIndex(in: request.segments) {
            request.includesSegmentStartingAtEnd ? $0.range.start > end : $0.range.start >= end
        }
        return request.segments[first..<max(first, last)]
    }

    static func visibleRuns(_ request: VisibleRequest) -> [VisibleRun] {
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0, request.viewport.width > 0,
            !request.segments.isEmpty
        else { return [] }
        let scale = request.pixelScale.isFinite && request.pixelScale > 0 ? request.pixelScale : 1
        let pixelCount = max(1, Int(ceil(request.viewport.width * scale)))
        var runs: [VisibleRun] = []
        var current: (pixel: Int, segment: SilenceTimelineSegment, selected: Bool, hovered: Bool)?
        func flush(_ pixel: Int) {
            guard let current else { return }
            let width = CGFloat(pixel - current.pixel) / scale
            runs.append(
                VisibleRun(
                    x: CGFloat(current.pixel) / scale,
                    width: width,
                    duration: current.segment.range.duration,
                    classification: current.segment.classification,
                    isSelected: current.selected,
                    isHovered: current.hovered
                ))
        }
        for pixel in 0..<pixelCount {
            let displayX = request.viewport.lowerBound + (CGFloat(pixel) + 0.5) / scale
            let time = request.projection.takeTime(Double(displayX / request.pixelsPerSecond))
            guard let segment = at(.init(segments: request.segments, time: time)) else {
                if current != nil {
                    flush(pixel)
                    current = nil
                }
                continue
            }
            let selected = contains(segment.range, in: request.selections)
            let hovered = request.hoveredRange == segment.range
            if let active = current,
                active.segment == segment, active.selected == selected,
                active.hovered == hovered
            {
                continue
            }
            flush(pixel)
            current = (
                pixel: pixel, segment: segment, selected: selected, hovered: hovered
            )
        }
        flush(pixelCount)
        return runs
    }

    static func contains(_ range: EditorTimeRange, in selections: [EditorTimeRange]) -> Bool {
        guard !selections.isEmpty else { return false }
        let index = firstIndex(in: selections) { $0.start >= range.start }
        return selections.indices.contains(index) && selections[index] == range
    }

    private static func firstIndex(
        in segments: [SilenceTimelineSegment], where predicate: (SilenceTimelineSegment) -> Bool
    ) -> Int {
        var lower = 0
        var upper = segments.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(segments[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }

    private static func firstIndex(
        in ranges: [EditorTimeRange], where predicate: (EditorTimeRange) -> Bool
    ) -> Int {
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(ranges[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}

struct EditorTimelineSilenceOverlay: View, Equatable {
    struct Configuration: Equatable {
        let segments: [SilenceTimelineSegment]
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let viewport: EditorTimelineViewport
        let rows: [Range<CGFloat>]
    }

    let configuration: Configuration
    @Environment(\.displayScale) private var displayScale

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.configuration == rhs.configuration
    }

    var body: some View {
        let runs = SilenceTimelineSegments.visibleRuns(.init(
            segments: configuration.segments, projection: configuration.projection,
            pixelsPerSecond: configuration.pixelsPerSecond, viewport: configuration.viewport,
            selections: [], hoveredRange: nil, pixelScale: displayScale))
        Canvas { context, _ in
            for run in runs where run.classification == .silence {
                for row in configuration.rows {
                    let rect = CGRect(x: run.x, y: row.lowerBound, width: run.width,
                                      height: row.upperBound - row.lowerBound)
                    context.fill(Path(rect), with: .color(BlitzUI.recordRed.opacity(0.22)))
                    context.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2)),
                                 with: .color(BlitzUI.recordRed.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
