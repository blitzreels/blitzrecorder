import SwiftUI

struct EditorVideoClipLayout: Equatable {
    struct Request: Equatable {
        let projection: EditorTimelineProjection
        let splits: [Double]
    }

    struct Clip: Equatable, Identifiable {
        let id: Int
        let range: EditorTimeRange
        let start: Double
        let end: Double
        var title: String { "Clip \(id + 1)" }
    }

    struct Run: Identifiable {
        let clip: Clip
        let x: CGFloat
        let width: CGFloat
        var id: Int { clip.id }
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
                result.append(.init(id: result.count, range: .init(start: start, end: end),
                    start: fragment.start + start - fragment.takeStart, end: fragment.start + end - fragment.takeStart))
                start = end
                splitIndex += 1
            }
            result.append(.init(id: result.count, range: .init(start: start, end: fragment.takeEnd),
                start: fragment.start + start - fragment.takeStart, end: fragment.end))
        }
        clips = result
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
        var previousID: Int?
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
        let onSelect: (EditorTimelineRangeClick) -> Void
    }

    let configuration: Configuration

    var body: some View {
        let runs = configuration.layout.runs(.init(
            viewport: configuration.viewport, pixelsPerSecond: configuration.pixelsPerSecond))
        Canvas { context, size in
            for run in runs {
                let rect = CGRect(x: run.x + 2, y: 2, width: max(1, run.width - 4), height: size.height - 4)
                let path = Path(roundedRect: rect, cornerRadius: run.width >= 8 ? 4 : 0)
                context.fill(path, with: .color(BlitzUI.mint.opacity(0.12)))
                context.stroke(path, with: .color(BlitzUI.mint.opacity(0.3)), lineWidth: 1)
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
        .pointingHandCursor()
        .gesture(SpatialTapGesture().onEnded { event in
            if let clip = configuration.layout.clip(at: Double(event.location.x / configuration.pixelsPerSecond)) {
                configuration.onSelect(.init(range: clip.range, modifiers: NSEvent.modifierFlags))
            }
        })
        .overlay(alignment: .topLeading) {
            ForEach(runs.filter { $0.width >= 28 }) { run in
                Button {
                    configuration.onSelect(.init(range: run.clip.range, modifiers: NSEvent.modifierFlags))
                } label: {
                    Color.clear.frame(width: run.width, height: configuration.height).contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .offset(x: configuration.viewport.lowerBound + run.x)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video clips")
        .accessibilityValue("\(configuration.layout.clips.count) clips")
        .help("⌘B splits at the playhead. Click a clip to select it; Delete removes it from all source tracks.")
    }
}

struct EditorVideoClipSeams: View {
    struct Configuration {
        let layout: EditorVideoClipLayout
        let viewport: EditorTimelineViewport
        let pixelsPerSecond: CGFloat
        let height: CGFloat
    }

    let configuration: Configuration

    var body: some View {
        let runs = configuration.layout.runs(.init(
            viewport: configuration.viewport, pixelsPerSecond: configuration.pixelsPerSecond))
        Canvas { context, size in
            for run in runs where run.clip.id > 0 {
                let x = CGFloat(run.clip.start) * configuration.pixelsPerSecond - configuration.viewport.lowerBound
                guard x >= 0, x < size.width else { continue }
                context.fill(Path(CGRect(x: x - 2, y: 0, width: 5, height: size.height)),
                    with: .color(BlitzUI.projectLibraryBackground))
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                    with: .color(.white.opacity(0.65)))
            }
        }
        .frame(width: configuration.viewport.width, height: configuration.height)
        .offset(x: configuration.viewport.lowerBound)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
