import AppKit
import SwiftUI

enum EditorTimelineClipPointer: Equatable {
    static let handleWidth: CGFloat = 12

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

    struct Request {
        let layout: EditorVideoClipLayout
        let edits: TimelineEdits
        let duration: Double
        let pixelsPerSecond: CGFloat
        let x: CGFloat
        var edgeWidth: CGFloat = EditorTimelineClipPointer.handleWidth
        var isTrimming: Bool = false
    }

    static func at(_ request: Request) -> Self {
        if request.isTrimming { return .resize }
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0, request.x.isFinite else {
            return .arrow
        }
        if let clip = request.layout.clip(at: Double((request.x + request.edgeWidth / 3) / request.pixelsPerSecond)) {
            let startX = CGFloat(clip.start) * request.pixelsPerSecond
            if request.x >= startX,
                request.x < startX + request.edgeWidth { return .resize }
        }
        let trailingWidth = request.edgeWidth / 3
        if let edgeClip = request.layout.clip(at: Double((request.x - trailingWidth) / request.pixelsPerSecond)) {
            let endX = CGFloat(edgeClip.end) * request.pixelsPerSecond
            if request.x >= endX - request.edgeWidth + trailingWidth,
                EditorVideoCuts.canTrimRight(.init(
                    edits: request.edits, clip: edgeClip.range,
                    nextClipStart: request.layout.next(after: edgeClip)?.range.start,
                    duration: request.duration
                )) {
                return .resize
            }
        }
        return request.layout.clip(at: Double(request.x / request.pixelsPerSecond)) == nil ? .arrow : .pointingHand
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
        guard clips.indices.contains(clip.index), clips[clip.index].id == clip.id,
            clip.index + 1 < clips.count else { return nil }
        return clips[clip.index + 1]
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
        let trimOrigin: EditorClipTrimSession.Origin?
        let onSelect: (EditorTimelineRangeClick) -> Void
        let onHover: (EditorTimeRange?) -> Void
        let onBeginTrim: (EditorClipTrimSession.Origin) -> Void
        let onTrim: (CGFloat) -> Void
        let onEndTrim: () -> Void
        let onCancelTrim: () -> Void
    }

    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var pointer = EditorTimelineClipPointer.arrow
    @State private var hoveredHandle: EditorVideoClipLayout.Clip.ID?
    @State private var trimHandleRun: EditorVideoClipLayout.Run?

    var body: some View {
        let runs = configuration.layout.runs(.init(
            viewport: configuration.viewport, pixelsPerSecond: configuration.pixelsPerSecond))
        Canvas { context, size in
            for run in runs {
                let hovered = isHovered(run)
                let rect = CGRect(x: run.x, y: 2, width: max(1, run.width), height: size.height - 4)
                let path = Path(roundedRect: rect, cornerRadius: run.width >= 8 ? 4 : 0)
                context.fill(path, with: .color(BlitzUI.mint.opacity(hovered ? 0.26 : 0.12)))
                context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: 3)
                context.stroke(path, with: .color(hovered ? BlitzUI.mint : BlitzUI.strongFill), lineWidth: hovered ? 2 : 1)
                guard run.width >= 64, hovered || isSelected(run) else { continue }
                var clipped = context
                clipped.clip(to: path)
                clipped.fill(Path(CGRect(x: rect.minX, y: rect.maxY - 19, width: rect.width, height: 19)),
                             with: .color(.black.opacity(0.8)))
                clipped.draw(Text(run.clip.title).font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.primaryText),
                    at: CGPoint(x: rect.minX + 8, y: rect.maxY - 10), anchor: .leading)
                if run.width >= 140 {
                    clipped.draw(Text(String(format: "%.1fs", run.clip.end - run.clip.start))
                        .font(BlitzType.footnote).monospacedDigit()
                        .foregroundStyle(BlitzUI.secondaryText),
                        at: CGPoint(x: rect.maxX - 8, y: rect.maxY - 10), anchor: .trailing)
                }
            }
        }
        .frame(width: configuration.viewport.width, height: configuration.height)
        .offset(x: configuration.viewport.lowerBound)
        .frame(width: configuration.width, height: configuration.height, alignment: .leading)
        .contentShape(.rect)
        .blitzCursor(pointer.cursor)
        .gesture(SpatialTapGesture().onEnded { event in
            if let clip = configuration.layout.clip(at: Double(event.location.x / configuration.pixelsPerSecond)) {
                configuration.onSelect(.init(range: clip.range, modifiers: NSEvent.modifierFlags))
            }
        })
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard isEnabled else { return }
                let target = EditorTimelineClipPointer.at(.init(
                    layout: configuration.layout, edits: configuration.edits,
                    duration: configuration.duration, pixelsPerSecond: configuration.pixelsPerSecond,
                    x: location.x, isTrimming: configuration.trimOrigin != nil
                ))
                if pointer != target { pointer = target }
                let range = configuration.layout.clip(at: Double(location.x / configuration.pixelsPerSecond))?.range
                if range != configuration.hoveredRange { configuration.onHover(range) }
            case .ended:
                configuration.onHover(nil)
                if configuration.trimOrigin == nil { pointer = .arrow }
            }
        }
        .onDisappear { cancelTrim() }
        .onChange(of: configuration.trimOrigin) { _, origin in
            if origin == nil { trimHandleRun = nil }
        }
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
                ForEach(trimmableRuns(runs)) { run in
                    trimHandle(.init(run: run, edge: .left))
                    trimHandle(.init(run: run, edge: .right))
                }
            }
            .frame(width: configuration.width, height: configuration.height, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video clips")
        .accessibilityValue("\(configuration.layout.clips.count) clips")
        .help("⌘B splits this clip at the playhead, including Screen, Camera, and audio. Drag either clip edge inward to shorten or outward to restore adjacent cut footage. Click a clip to select it; Delete removes it from all source tracks.")
    }

    private func isSelected(_ run: EditorVideoClipLayout.Run) -> Bool {
        configuration.selectedRanges.contains { abs($0.start - run.clip.range.start) <= 1.0 / 600 }
    }

    private func isHovered(_ run: EditorVideoClipLayout.Run) -> Bool {
        guard let hovered = configuration.hoveredRange else { return false }
        return abs(run.clip.range.start - hovered.start) <= 1.0 / 600
    }

    private func trimmableRuns(_ runs: [EditorVideoClipLayout.Run]) -> [EditorVideoClipLayout.Run] {
        if configuration.trimOrigin != nil, let trimHandleRun {
            return [trimHandleRun]
        }
        return runs
    }

    private func nextClipStart(_ clip: EditorVideoClipLayout.Clip) -> Double? {
        configuration.layout.next(after: clip)?.range.start
    }

    private struct HandleRequest {
        let run: EditorVideoClipLayout.Run
        let edge: EditorClipTrimSession.Edge
    }

    private func trimHandle(_ request: HandleRequest) -> some View {
        let run = request.run
        let edge = request.edge
        let origin = configuration.trimOrigin
        let isTrimming = origin?.clip == run.clip.range && origin?.edge == edge
        let isActive = hoveredHandle == run.clip.id || isTrimming
        let showsHandle = isSelected(run) || isActive || isHovered(run)
        let selected = configuration.selectedRanges.first
        let shift = isTrimming ? (edge == .left
            ? (selected?.start ?? run.clip.range.start) - run.clip.range.start
            : (selected?.end ?? run.clip.range.end) - run.clip.range.end) : 0
        let time = (edge == .left ? run.clip.start : run.clip.end) + shift
        let previousEnd = configuration.layout.clips.last { $0.range.end <= run.clip.range.start }?.range.end
        return EditorTimelineGrip(tint: BlitzUI.mint, isActive: isActive)
        .opacity(showsHandle ? 1 : 0)
        .frame(width: EditorTimelineClipPointer.handleWidth, height: configuration.height)
        .contentShape(.rect)
        .blitzCursor(.resizeLeftRight)
        .onHover { hovering in
            hoveredHandle = hovering && isEnabled ? run.clip.id : nil
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    if configuration.trimOrigin == nil { trimHandleRun = run }
                    configuration.onBeginTrim(.init(
                        edits: configuration.edits, clip: run.clip.range,
                        nextClipStart: nextClipStart(run.clip),
                        pixelsPerSecond: configuration.pixelsPerSecond, duration: configuration.duration,
                        edge: edge, previousClipEnd: previousEnd
                    ))
                    configuration.onTrim(value.translation.width)
                }
                .onEnded { value in
                    configuration.onTrim(value.translation.width)
                    configuration.onEndTrim()
                }
        )
        .fixedSize()
        .help("Drag inward to shorten or outward to restore adjacent cut footage. All source tracks stay in sync.")
        .accessibilityLabel("Trim \(edge.rawValue) edge of \(run.clip.title)")
        .accessibilityValue("Drag inward to shorten or outward to restore cut footage")
        .timelineControl(id: "trim-\(run.clip.id.ticks)-\(edge.rawValue)")
        .offset(x: CGFloat(time) * configuration.pixelsPerSecond - (edge == .right
            ? EditorTimelineClipPointer.handleWidth : 0))
    }

    private func cancelTrim() {
        configuration.onCancelTrim()
        configuration.onHover(nil)
        hoveredHandle = nil
        trimHandleRun = nil
        pointer = .arrow
    }
}
