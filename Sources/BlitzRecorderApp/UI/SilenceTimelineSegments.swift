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

    static func at(_ request: Lookup) -> SilenceTimelineSegment? {
        guard request.time.isFinite else { return nil }
        return request.segments.first { request.time >= $0.range.start && request.time < $0.range.end }
    }

    static func neighbor(_ request: Navigation) -> SilenceTimelineSegment? {
        switch request.direction {
        case .previous:
            request.segments.last { $0.range.end <= request.selection.start + 1.0 / 600 }
        case .next:
            request.segments.first { $0.range.start >= request.selection.end - 1.0 / 600 }
        }
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

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(configuration.segments) { segment in
                let start = max(configuration.viewport.lowerBound,
                                CGFloat(configuration.projection.displayTime(segment.range.start)) * configuration.pixelsPerSecond)
                let end = min(configuration.viewport.upperBound,
                              CGFloat(configuration.projection.displayTime(segment.range.end)) * configuration.pixelsPerSecond)
                if end > start {
                    cell(.init(segment: segment, width: end - start))
                        .offset(x: start)
                }
            }
        }
        .frame(width: configuration.width, height: configuration.height, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sound and silence segments")
    }

    private struct Cell {
        let segment: SilenceTimelineSegment
        let width: CGFloat
    }

    private func cell(_ cell: Cell) -> some View {
        let segment = cell.segment
        let selected = configuration.selections.contains(segment.range)
        let hovered = configuration.hoveredRange == segment.range
        let color = segment.classification == .silence ? BlitzUI.recordRed : BlitzUI.mint
        let gap: CGFloat = cell.width > 4 ? 2 : 0
        return Button {
            configuration.onSelect(segment.range)
        } label: {
            HStack(spacing: 5) {
                if cell.width >= 24 {
                    Image(systemName: segment.symbol)
                }
                if cell.width >= 72 {
                    Text(segment.title)
                }
                if cell.width >= 128 {
                    Text(String(format: "%.1fs", segment.range.duration))
                        .monospacedDigit()
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(selected ? Color.white : color)
            .frame(width: max(0.5, cell.width - gap), height: configuration.height - 4)
            .background(color.opacity(selected ? 0.3 : hovered ? 0.24 : 0.12), in: .rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(selected ? Color.white : hovered ? color : color.opacity(0.35),
                                  lineWidth: selected || hovered ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .pointingHandCursor()
        .onHover { configuration.onHover($0 ? segment.range : nil) }
        .accessibilityLabel("\(segment.title) segment, \(SilenceTime.label(segment.range.start)) to \(SilenceTime.label(segment.range.end))")
        .accessibilityValue(selected ? "Selected" : segment.classification == .silence ? "Marked for removal" : "Kept")
        .help("\(segment.title) · \(String(format: "%.2f seconds", segment.range.duration)). Click to select. ⌘-click to add or remove. Shift-click or drag to select several. Right-click to mark.")
        .accessibilityAction(named: selected ? "Remove from selection" : "Add to selection") {
            configuration.onToggleSelection(segment.range)
        }
        .contextMenu {
            Button(selected ? "Remove from selection" : "Add to selection", systemImage: selected ? "minus" : "plus") {
                configuration.onToggleSelection(segment.range)
            }
            Divider()
            Button("Mark as sound", systemImage: "waveform") {
                configuration.onClassify(.init(range: segment.range, classification: .sound))
            }
            Button("Mark as silence", systemImage: "waveform.slash") {
                configuration.onClassify(.init(range: segment.range, classification: .silence))
            }
        }
    }
}
