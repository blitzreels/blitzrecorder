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

struct SilenceSegmentStrip: View {
    struct Configuration {
        let segments: [SilenceTimelineSegment]
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let viewport: EditorTimelineViewport
        let width: CGFloat
        let height: CGFloat
        let selections: [EditorTimeRange]
        let hoveredRange: EditorTimeRange?
        let onSelect: (EditorTimeRange) -> Void
        let onToggleSelection: (EditorTimeRange) -> Void
        let onHover: (EditorTimeRange?) -> Void
        let onClassify: (SilenceEditingSession.ClassificationRequest) -> Void
    }

    let configuration: Configuration
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let runs = SilenceTimelineSegments.visibleRuns(
            .init(
                segments: configuration.segments,
                projection: configuration.projection,
                pixelsPerSecond: configuration.pixelsPerSecond,
                viewport: configuration.viewport,
                selections: configuration.selections,
                hoveredRange: configuration.hoveredRange,
                pixelScale: displayScale
            ))
        SilenceSegmentStripCanvas(runs: runs)
            .equatable()
            .frame(width: configuration.viewport.width, height: configuration.height)
            .offset(x: configuration.viewport.lowerBound)
            .frame(width: configuration.width, height: configuration.height, alignment: .leading)
            .contentShape(.rect)
            .pointingHandCursor()
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    select(at: event.location.x)
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    configuration.onHover(segment(at: location.x)?.range)
                case .ended:
                    configuration.onHover(nil)
                }
            }
            .contextMenu {
                if let range = configuration.hoveredRange ?? configuration.selections.first {
                    Button(
                        configuration.selections.contains(range) ? "Remove from selection" : "Add to selection",
                        systemImage: configuration.selections.contains(range) ? "minus" : "plus"
                    ) {
                        configuration.onToggleSelection(range)
                    }
                    Divider()
                    Button("Mark as sound", systemImage: "waveform") {
                        configuration.onClassify(.init(range: range, classification: .sound))
                    }
                    Button("Mark as silence", systemImage: "waveform.slash") {
                        configuration.onClassify(.init(range: range, classification: .silence))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sound and silence segments")
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if let range = configuration.selections.first {
                    configuration.onSelect(range)
                }
            }
            .accessibilityAdjustableAction { direction in
                let selected = configuration.selections.first ?? configuration.hoveredRange
                let neighbor: SilenceTimelineSegment?
                switch direction {
                case .increment:
                    if let selected {
                        neighbor = SilenceTimelineSegments.neighbor(
                            .init(segments: configuration.segments, selection: selected, direction: .next))
                    } else {
                        neighbor = configuration.segments.first
                    }
                case .decrement:
                    if let selected {
                        neighbor = SilenceTimelineSegments.neighbor(
                            .init(segments: configuration.segments, selection: selected, direction: .previous))
                    } else {
                        neighbor = configuration.segments.last
                    }
                @unknown default:
                    neighbor = nil
                }
                if let neighbor {
                    configuration.onSelect(neighbor.range)
                }
            }
            .help(
                "Click to select. ⌘-click to add or remove. Shift-click or drag to select several. Right-click to mark."
            )
    }

    private var accessibilityValue: String {
        if configuration.selections.count > 1 {
            return "\(configuration.selections.count) segments selected"
        }
        if let range = configuration.selections.first,
            let segment = SilenceTimelineSegments.at(
                .init(segments: configuration.segments, time: range.start))
        {
            return "\(segment.title) selected, \(SilenceTime.label(range.start)) to \(SilenceTime.label(range.end))"
        }
        return "\(configuration.segments.count) segments"
    }

    private func select(at x: CGFloat) {
        guard let segment = segment(at: x) else { return }
        configuration.onSelect(segment.range)
    }

    private func segment(at x: CGFloat) -> SilenceTimelineSegment? {
        guard configuration.pixelsPerSecond > 0 else { return nil }
        return SilenceTimelineSegments.at(
            .init(
                segments: configuration.segments,
                time: configuration.projection.takeTime(Double(x / configuration.pixelsPerSecond))
            ))
    }
}

private struct SilenceSegmentStripCanvas: View, Equatable {
    let runs: [SilenceTimelineSegments.VisibleRun]

    var body: some View {
        Canvas { context, size in
            for run in runs {
                let color = run.classification == .silence ? BlitzUI.recordRed : BlitzUI.mint
                let rect = CGRect(x: run.x, y: 2, width: max(0.5, run.width), height: size.height - 4)
                let path = Path(roundedRect: rect, cornerRadius: run.width > 4 ? 4 : 0)
                context.fill(
                    path,
                    with: .color(color.opacity(run.isSelected ? 0.3 : run.isHovered ? 0.24 : 0.12)))
                if run.isSelected || run.isHovered {
                    context.stroke(
                        path,
                        with: .color(run.isSelected ? Color.white : color),
                        lineWidth: 2)
                }
                if run.width >= 24 {
                    var clipped = context
                    clipped.clip(to: path)
                    let title = run.classification == .silence ? "Silence" : "Sound"
                    let symbol = run.classification == .silence ? "waveform.slash" : "waveform"
                    let foreground = run.isSelected ? Color.white : color
                    var image = clipped.resolve(Image(systemName: symbol))
                    image.shading = .color(foreground)
                    clipped.draw(image, at: CGPoint(x: rect.minX + 12, y: rect.midY), anchor: .center)
                    if run.width >= 72 {
                        clipped.draw(
                            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(foreground),
                            at: CGPoint(x: rect.minX + 22, y: rect.midY),
                            anchor: .leading)
                    }
                    if run.width >= 128 {
                        clipped.draw(
                            Text(String(format: "%.1fs", run.duration))
                                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(BlitzUI.secondaryText),
                            at: CGPoint(x: rect.maxX - 8, y: rect.midY),
                            anchor: .trailing)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
