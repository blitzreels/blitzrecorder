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
