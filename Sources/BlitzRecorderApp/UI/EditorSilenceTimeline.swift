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

    static func selectedRange(_ request: SelectionRequest) -> EditorTimeRange? {
        if let band = request.bands.first(where: { request.x >= $0.x && request.x <= $0.x + $0.width }) {
            return band.range
        }
        return request.bands.filter { request.x >= $0.x - 2 && request.x <= $0.x + $0.width + 2 }
            .min { abs($0.x + $0.width / 2 - request.x) < abs($1.x + $1.width / 2 - request.x) }?.range
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
}

struct SilenceWaveformOverlay: View, Equatable {
    let bands: [SilenceTimelineBands.Band]
    let viewport: EditorTimelineViewport
    let selection: EditorTimeRange?

    var body: some View {
        Canvas { context, size in
            for band in bands {
                let isSelected = selection == band.range
                let color = isSelected || !band.isEnabled ? BlitzUI.mint : BlitzUI.warning
                let rect = CGRect(x: band.x, y: 0, width: band.width, height: size.height)
                context.fill(Path(rect), with: .color(color.opacity(isSelected ? 0.25 : 0.18)))
                context.stroke(
                    Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                    with: .color(color.opacity(isSelected ? 0.9 : 0.5)), lineWidth: 1)
            }
        }
        .frame(width: viewport.width)
        .offset(x: viewport.lowerBound)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
