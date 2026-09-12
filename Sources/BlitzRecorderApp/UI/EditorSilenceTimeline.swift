import SwiftUI

struct SilenceTimelineMetrics: Equatable {
    struct Request {
        let duration: Double
        let proposed: [TimelineCut]
        let saved: [TimelineCut]
    }

    let pauseCount: Int
    let removedDuration: Double
    let outputDuration: Double
    let hasChanges: Bool

    init(_ request: Request) {
        let duration = TimelineTimeMap.time(request.duration.isFinite ? max(0, request.duration) : 0)
        let proposed = TimelineTimeMap(takeDuration: duration, cuts: request.proposed)
        let saved = TimelineTimeMap(takeDuration: duration, cuts: request.saved)
        pauseCount = request.proposed.filter { $0.kind == .silence && $0.isEnabled }.count
        removedDuration = proposed.removedDuration
        outputDuration = proposed.outputDuration.seconds
        let proposedExclusions = TimelineTimeMap(
            takeDuration: duration,
            cuts: request.proposed.filter { !$0.isEnabled }.map {
                var cut = $0
                cut.isEnabled = true
                return cut
            })
        let savedExclusions = TimelineTimeMap(
            takeDuration: duration,
            cuts: request.saved.filter { !$0.isEnabled }.map {
                var cut = $0
                cut.isEnabled = true
                return cut
            })
        hasChanges =
            proposed.keptRanges != saved.keptRanges || proposedExclusions.keptRanges != savedExclusions.keptRanges
    }
}

struct SilenceTimelineBands {
    struct Request {
        let cuts: [TimelineCut]
        let projection: EditorTimelineProjection
        let pixelsPerSecond: CGFloat
        let viewport: EditorTimelineViewport
    }

    struct Band: Equatable {
        let range: EditorTimeRange
        let x: CGFloat
        let width: CGFloat
        let isEnabled: Bool
    }

    struct SelectionRequest {
        let bands: [Band]
        let x: CGFloat
    }

    struct SoundRangeRequest {
        let cuts: [TimelineCut]
        let time: Double
        let duration: Double
    }

    static func soundRange(_ request: SoundRangeRequest) -> EditorTimeRange? {
        guard request.time.isFinite, request.duration.isFinite, request.duration > 0,
            request.time >= 0, request.time <= request.duration else { return nil }
        let cuts = request.cuts.filter {
            $0.kind == .silence && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
        }
        guard !cuts.contains(where: { request.time >= $0.start && request.time < $0.end }) else { return nil }
        let start = cuts.filter { $0.end <= request.time }.map(\.end).max() ?? 0
        let end = cuts.filter { $0.start > request.time }.map(\.start).min() ?? request.duration
        return EditorTimeRange.resolve(.init(anchor: start, head: end, duration: request.duration))
    }

    struct ClassificationRequest {
        let range: EditorTimeRange
        let cuts: [TimelineCut]
    }

    static func classification(_ request: ClassificationRequest) -> SilenceClassification {
        var cursor = request.range.start
        for cut in request.cuts.filter({ $0.kind == .silence && $0.isEnabled }).sorted(by: { $0.start < $1.start }) {
            guard cut.end > cursor else { continue }
            if cut.start > cursor + 1.0 / 600 { return .sound }
            cursor = cut.end
            if cursor >= request.range.end - 1.0 / 600 { return .silence }
        }
        return .sound
    }

    static func selectedRange(_ request: SelectionRequest) -> EditorTimeRange? {
        request.bands.first(where: { request.x >= $0.x && request.x < $0.x + $0.width })?.range
    }

    struct OverlayRun: Equatable {
        let x: CGFloat
        let width: CGFloat
        let isEnabled: Bool
        let isSelected: Bool
    }

    static func visible(_ request: Request) -> [Band] {
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0, request.viewport.width > 0 else {
            return []
        }
        return request.cuts.compactMap { cut in
            guard cut.kind == .silence, cut.start.isFinite, cut.end.isFinite, cut.end > cut.start else { return nil }
            let start = max(
                request.viewport.lowerBound,
                CGFloat(request.projection.displayTime(cut.start)) * request.pixelsPerSecond)
            let end = min(
                request.viewport.upperBound, CGFloat(request.projection.displayTime(cut.end)) * request.pixelsPerSecond)
            guard end - start > request.pixelsPerSecond / 300 else { return nil }
            return Band(
                range: EditorTimeRange(start: cut.start, end: cut.end),
                x: start - request.viewport.lowerBound, width: max(1, end - start), isEnabled: cut.isEnabled
            )
        }
    }

    static func overlayRuns(_ request: Request, selections: [EditorTimeRange], pixelScale: CGFloat = 1)
        -> [OverlayRun]
    {
        guard request.pixelsPerSecond.isFinite, request.pixelsPerSecond > 0, request.viewport.width > 0,
            !request.cuts.isEmpty
        else { return [] }
        let scale = pixelScale.isFinite && pixelScale > 0 ? pixelScale : 1
        let pixelCount = max(1, Int(ceil(request.viewport.width * scale)))
        var runs: [OverlayRun] = []
        var current: (pixel: Int, enabled: Bool, selected: Bool)?
        func flush(_ pixel: Int) {
            guard let current else { return }
            runs.append(
                OverlayRun(
                    x: CGFloat(current.pixel) / scale,
                    width: CGFloat(pixel - current.pixel) / scale,
                    isEnabled: current.enabled,
                    isSelected: current.selected
                ))
        }
        for pixel in 0..<pixelCount {
            let displayX = request.viewport.lowerBound + (CGFloat(pixel) + 0.5) / scale
            let time = request.projection.takeTime(Double(displayX / request.pixelsPerSecond))
            guard let cut = silenceCut(at: time, cuts: request.cuts) else {
                if current != nil {
                    flush(pixel)
                    current = nil
                }
                continue
            }
            let selected = SilenceTimelineSegments.contains(
                EditorTimeRange(start: cut.start, end: cut.end), in: selections)
            if let active = current, active.enabled == cut.isEnabled, active.selected == selected {
                continue
            }
            flush(pixel)
            current = (pixel: pixel, enabled: cut.isEnabled, selected: selected)
        }
        flush(pixelCount)
        return runs
    }

    static func silenceCut(at time: Double, cuts: [TimelineCut]) -> TimelineCut? {
        guard time.isFinite, !cuts.isEmpty else { return nil }
        let index = firstIndex(in: cuts) { $0.start > time } - 1
        guard cuts.indices.contains(index) else { return nil }
        let cut = cuts[index]
        guard cut.kind == .silence, cut.end > time else { return nil }
        return cut
    }

    private static func firstIndex(in cuts: [TimelineCut], where predicate: (TimelineCut) -> Bool) -> Int {
        var lower = 0
        var upper = cuts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if predicate(cuts[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}

struct SilenceWaveformOverlay: View, Equatable {
    let runs: [SilenceTimelineBands.OverlayRun]
    let viewport: EditorTimelineViewport

    var body: some View {
        Canvas { context, size in
            for run in runs {
                let color = run.isEnabled ? Color.red : BlitzUI.mint
                let rect = CGRect(x: run.x, y: 0, width: run.width, height: size.height)
                context.fill(Path(rect), with: .color(color.opacity(run.isSelected ? 0.25 : 0.18)))
                context.stroke(
                    Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                    with: .color(color.opacity(run.isSelected ? 0.9 : 0.5)), lineWidth: 1)
            }
        }
        .frame(width: viewport.width)
        .offset(x: viewport.lowerBound)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
