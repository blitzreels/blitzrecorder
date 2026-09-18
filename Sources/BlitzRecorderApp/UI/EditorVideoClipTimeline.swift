import AppKit
import SwiftUI

enum EditorTimelineClipPointer: Equatable {
    case arrow
    case pointingHand
    case resize

    var cursor: NSCursor {
        switch self {
        case .arrow: return .arrow
        case .pointingHand: return .pointingHand
        case .resize: return .resizeLeftRight
        }
    }

    func apply() {
        cursor.set()
    }

    struct Request {
        let layout: EditorVideoClipLayout
        let edits: TimelineEdits
        let duration: Double
        let pixelsPerSecond: CGFloat
        let x: CGFloat
        var edgeWidth: CGFloat = 12
        var isExpanding: Bool = false
    }

    static func at(_ request: Request) -> Self {
        if request.isExpanding { return .resize }
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0, request.x.isFinite else {
            return .arrow
        }
        guard let clip = request.layout.clip(at: Double(request.x / request.pixelsPerSecond)) else {
            return .arrow
        }
        let endX = CGFloat(clip.end) * request.pixelsPerSecond
        let onTrailingEdge = request.x >= endX - request.edgeWidth
        if onTrailingEdge, EditorVideoCuts.rightExpandLimit(.init(
            edits: request.edits, clip: clip.range, nextClipStart: request.layout.next(after: clip)?.range.start,
            duration: request.duration
        )) != nil {
            return .resize
        }
        return .pointingHand
    }
}

struct EditorVideoClipLayout: Equatable {
    struct Request: Equatable {
        let projection: EditorTimelineProjection
        let splits: [Double]
    }

    struct Clip: Equatable, Identifiable {
        struct ID: Hashable {
            let ticks: Int

            init(takeStart: Double) {
                ticks = Int((TimelineTimeMap.time(takeStart).seconds * Double(TimelineTimeMap.timescale)).rounded())
            }
        }

        let id: ID
        let index: Int
        let range: EditorTimeRange
        let start: Double
        let end: Double
        var title: String { "Clip \(index + 1)" }
    }

    struct Run: Identifiable {
        let clip: Clip
        let x: CGFloat
        let width: CGFloat
        var id: Clip.ID { clip.id }
    }

    struct Viewport {
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
    }

    let clips: [Clip]

    init(_ request: Request) {
        let splits = Array(Set(request.splits.filter(\.isFinite).map { TimelineTimeMap.time($0).seconds })).sorted()
        var splitIndex = 0
        var result: [Clip] = []
        for fragment in request.projection.fragments {
            while splitIndex < splits.count, splits[splitIndex] <= fragment.takeStart { splitIndex += 1 }
            var start = fragment.takeStart
            while splitIndex < splits.count, splits[splitIndex] < fragment.takeEnd {
                let end = splits[splitIndex]
                result.append(.init(
                    id: .init(takeStart: start), index: result.count, range: .init(start: start, end: end),
                    start: fragment.start + start - fragment.takeStart, end: fragment.start + end - fragment.takeStart
                ))
                start = end
                splitIndex += 1
            }
            result.append(.init(
                id: .init(takeStart: start), index: result.count, range: .init(start: start, end: fragment.takeEnd),
                start: fragment.start + start - fragment.takeStart, end: fragment.end
            ))
        }
        clips = result
    }

    func next(after clip: Clip) -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }), index + 1 < clips.count else { return nil }
        return clips[index + 1]
    }

    func clip(at time: Double) -> Clip? {
        guard time.isFinite else { return nil }
        var lower = 0
        var upper = clips.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if clips[middle].start <= time { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0, clips[lower - 1].end > time else { return nil }
        return clips[lower - 1]
    }

    func hoveredSeamTimes(_ range: EditorTimeRange?) -> [Double] {
        guard let range,
            let clip = clips.first(where: { abs($0.range.start - range.start) <= 1.0 / 600 })
        else { return [] }
        let end = clips.last?.end ?? clip.end
        return [clip.start, clip.end].filter { $0 > 1.0 / 600 && $0 < end - 1.0 / 600 }
    }

    func runs(_ request: Viewport) -> [Run] {
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0,
            request.viewport.width > 0 else { return [] }
        var runs: [Run] = []
        var previousID: Clip.ID?
        for pixel in 0..<Int(ceil(request.viewport.width)) {
            let x = request.viewport.lowerBound + CGFloat(pixel) + 0.5
            guard let clip = clip(at: Double(x / request.pixelsPerSecond)), clip.id != previousID else { continue }
            previousID = clip.id
            let start = max(request.viewport.lowerBound, CGFloat(clip.start) * request.pixelsPerSecond)
            let end = min(request.viewport.upperBound, CGFloat(clip.end) * request.pixelsPerSecond)
            runs.append(.init(clip: clip, x: start - request.viewport.lowerBound, width: max(1, end - start)))
        }
        return runs
    }
}

struct EditorVideoClipStrip: View {
    struct Configuration {
        let layout: EditorVideoClipLayout
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
        let width: CGFloat
        let height: CGFloat
        let edits: TimelineEdits
        let duration: Double
        let selectedRanges: [EditorTimeRange]
        let hoveredRange: EditorTimeRange?
        let onSelect: (EditorTimelineRangeClick) -> Void
        let onHover: (EditorTimeRange?) -> Void
        let onPreviewExtend: (TimelineEdits?) -> Void
        let onEndExtend: (TimelineEdits?) -> Void
    }

    private struct ExpandOrigin {
        let edits: TimelineEdits
        let clip: EditorTimeRange
        let nextClipStart: Double?
        let pixelsPerSecond: CGFloat
    }

    let configuration: Configuration
    @State private var expandOrigin: ExpandOrigin?

    var body: some View {
        let runs = configuration.layout.runs(.init(
            viewport: configuration.viewport, pixelsPerSecond: configuration.pixelsPerSecond))
        Canvas { context, size in
            for run in runs {
                let hovered = isHovered(run)
                let rect = CGRect(x: run.x, y: 2, width: max(1, run.width), height: size.height - 4)
                let path = Path(roundedRect: rect, cornerRadius: run.width >= 8 ? 4 : 0)
                context.fill(path, with: .color(BlitzUI.mint.opacity(hovered ? 0.18 : 0.12)))
                if hovered {
                    context.stroke(path, with: .color(BlitzUI.mint.opacity(0.55)), lineWidth: 1)
                }
                guard run.width >= 64 else { continue }
                var clipped = context
                clipped.clip(to: path)
                clipped.draw(Text(run.clip.title).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BlitzUI.mint),
                    at: CGPoint(x: rect.minX + 8, y: rect.midY), anchor: .leading)
                if run.width >= 140 {
                    clipped.draw(Text(String(format: "%.1fs", run.clip.end - run.clip.start))
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(BlitzUI.secondaryText),
                        at: CGPoint(x: rect.maxX - 8, y: rect.midY), anchor: .trailing)
                }
            }
        }
        .frame(width: configuration.viewport.width, height: configuration.height)
        .offset(x: configuration.viewport.lowerBound)
        .frame(width: configuration.width, height: configuration.height, alignment: .leading)
        .contentShape(.rect)
        .gesture(SpatialTapGesture().onEnded { event in
            if let clip = configuration.layout.clip(at: Double(event.location.x / configuration.pixelsPerSecond)) {
                configuration.onSelect(.init(range: clip.range, modifiers: NSEvent.modifierFlags))
            }
        })
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let pointer = EditorTimelineClipPointer.at(.init(
                    layout: configuration.layout, edits: configuration.edits,
                    duration: configuration.duration, pixelsPerSecond: configuration.pixelsPerSecond,
                    x: location.x, isExpanding: expandOrigin != nil
                ))
                pointer.apply()
                configuration.onHover(
                    configuration.layout.clip(at: Double(location.x / configuration.pixelsPerSecond))?.range)
            case .ended:
                configuration.onHover(nil)
                if expandOrigin == nil { EditorTimelineClipPointer.arrow.apply() }
            }
        }
        .onDisappear { EditorTimelineClipPointer.arrow.apply() }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(runs.filter { $0.width >= 28 }) { run in
                    Button {
                        configuration.onSelect(.init(range: run.clip.range, modifiers: NSEvent.modifierFlags))
                    } label: {
                        Color.clear
                    }
                    .frame(width: run.width, height: configuration.height)
                    .contentShape(.rect)
                    .buttonStyle(BlitzPressButtonStyle())
                    .offset(x: configuration.viewport.lowerBound + run.x)
                    .fixedSize()
                    .accessibilityLabel(run.clip.title)
                    .accessibilityValue("\(SilenceTime.label(run.clip.start)) to \(SilenceTime.label(run.clip.end))")
                    .accessibilityAction(named: "Extend selection") {
                        configuration.onSelect(.init(range: run.clip.range, modifiers: .shift))
                    }
                    .accessibilityAction(named: "Toggle selection") {
                        configuration.onSelect(.init(range: run.clip.range, modifiers: .command))
                    }
                }
            }
            .frame(width: configuration.width, height: configuration.height, alignment: .leading)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(expandableRuns(runs)) { run in
                    expandHandle(run)
                }
            }
            .frame(width: configuration.width, height: configuration.height, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video clips")
        .accessibilityValue("\(configuration.layout.clips.count) clips")
        .help("⌘B splits this clip at the playhead, including Screen, Camera, and audio. Drag a clip’s right edge to restore the cut after it until the next clip. Click a clip to select it; Delete removes it from all source tracks.")
    }

    private func isHovered(_ run: EditorVideoClipLayout.Run) -> Bool {
        guard let hovered = configuration.hoveredRange else { return false }
        return abs(run.clip.range.start - hovered.start) <= 1.0 / 600
    }

    private func expandableRuns(_ runs: [EditorVideoClipLayout.Run]) -> [EditorVideoClipLayout.Run] {
        runs.filter { run in
            if let expandOrigin {
                return abs(run.clip.range.start - expandOrigin.clip.start) <= 1.0 / 600
            }
            return EditorVideoCuts.rightExpandLimit(.init(
                edits: configuration.edits, clip: run.clip.range,
                nextClipStart: nextClipStart(run.clip), duration: configuration.duration
            )) != nil
        }
    }

    private func nextClipStart(_ clip: EditorVideoClipLayout.Clip) -> Double? {
        configuration.layout.next(after: clip)?.range.start
    }

    private func expandHandle(_ run: EditorVideoClipLayout.Run) -> some View {
        let isSelected = configuration.selectedRanges.contains {
            abs($0.start - run.clip.range.start) <= 1.0 / 600
        }
        let showsHandle = isSelected || expandOrigin != nil || isHovered(run)
        return HStack {
            Spacer(minLength: 0)
            Capsule().fill(isSelected || expandOrigin != nil ? BlitzUI.mint : BlitzUI.mint.opacity(0.55))
                .frame(width: 3, height: 16)
                .opacity(showsHandle ? 1 : 0)
        }
        .frame(width: 12, height: configuration.height)
        .contentShape(.rect)
        .blitzCursor(.resizeLeftRight)
        .onHover { hovering in
            if hovering { EditorTimelineClipPointer.resize.apply() }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    let origin = expandOrigin ?? ExpandOrigin(
                        edits: configuration.edits, clip: run.clip.range,
                        nextClipStart: nextClipStart(run.clip),
                        pixelsPerSecond: configuration.pixelsPerSecond
                    )
                    if expandOrigin == nil {
                        expandOrigin = origin
                        configuration.onSelect(.init(range: origin.clip, modifiers: []))
                    }
                    configuration.onPreviewExtend(EditorVideoCuts.extendingRight(.init(
                        edits: origin.edits, clip: origin.clip, nextClipStart: origin.nextClipStart,
                        duration: configuration.duration,
                        delta: Double(value.translation.width / origin.pixelsPerSecond)
                    )))
                }
                .onEnded { value in
                    let origin = expandOrigin
                    expandOrigin = nil
                    let edits = origin.flatMap { origin in
                        EditorVideoCuts.extendingRight(.init(
                            edits: origin.edits, clip: origin.clip, nextClipStart: origin.nextClipStart,
                            duration: configuration.duration,
                            delta: Double(value.translation.width / origin.pixelsPerSecond)
                        ))
                    }
                    if let origin {
                        configuration.onSelect(.init(
                            range: EditorVideoCuts.dragRight(.init(
                                edits: origin.edits, clip: origin.clip, nextClipStart: origin.nextClipStart,
                                duration: configuration.duration,
                                delta: Double(value.translation.width / origin.pixelsPerSecond)
                            )).selection,
                            modifiers: []
                        ))
                    }
                    configuration.onEndExtend(edits)
                }
        )
        .fixedSize()
        .offset(x: configuration.viewport.lowerBound + run.x + run.width - 8)
        .help("Drag right to restore footage into this clip until the next clip starts. Screen, Camera, and audio stay in sync.")
        .accessibilityLabel("Extend \(run.clip.title)")
        .accessibilityValue("Drag right to restore the cut after this clip")
    }
}

struct EditorVideoClipSeams: View {
    struct Configuration {
        let layout: EditorVideoClipLayout
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
        let height: CGFloat
        let hoveredRange: EditorTimeRange?
    }

    let configuration: Configuration
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let times = configuration.layout.hoveredSeamTimes(configuration.hoveredRange)
        let hairline = max(1 / max(displayScale, 1), 0.5)
        Canvas { context, size in
            for time in times {
                let x = CGFloat(time) * configuration.pixelsPerSecond - configuration.viewport.lowerBound
                guard x >= 0, x < size.width else { continue }
                context.fill(
                    Path(CGRect(x: x, y: 0, width: hairline, height: size.height)),
                    with: .color(.white.opacity(0.22))
                )
            }
        }
        .frame(width: configuration.viewport.width, height: configuration.height)
        .offset(x: configuration.viewport.lowerBound)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
