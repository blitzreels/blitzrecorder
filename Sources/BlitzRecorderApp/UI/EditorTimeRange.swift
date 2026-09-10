import CoreMedia
import Foundation

struct EditorProjectSegmentDeletion {
    let index: Int
    let duration: Double
}

struct EditorTimeRange: Equatable {
    struct Request {
        let anchor: Double
        let head: Double
        let duration: Double
    }

    let start: Double
    let end: Double

    var duration: Double { end - start }
    var canCut: Bool { duration >= 1.0 / 600 }

    struct SegmentRequest {
        let eventTimes: [Double]
        let index: Int
        let duration: Double
    }

    static func segment(_ request: SegmentRequest) -> Self? {
        guard request.eventTimes.indices.contains(request.index) else { return nil }
        let end = request.index + 1 < request.eventTimes.count
            ? request.eventTimes[request.index + 1] : request.duration
        return resolve(.init(anchor: request.eventTimes[request.index], head: end, duration: request.duration))
    }

    static func resolve(_ request: Request) -> Self? {
        guard request.anchor.isFinite, request.head.isFinite,
            request.duration.isFinite, request.duration > 0
        else { return nil }
        let anchor = min(request.duration, max(0, request.anchor))
        let head = min(request.duration, max(0, request.head))
        return Self(start: min(anchor, head), end: max(anchor, head))
    }

    struct CutRequest {
        let range: EditorTimeRange
        let edits: TimelineEdits
        let takeDuration: Double
    }

    static func removing(_ request: CutRequest) -> TimelineEdits? {
        guard
            let range = resolve(
                .init(
                    anchor: request.range.start, head: request.range.end, duration: request.takeDuration
                )), range.canCut
        else { return nil }
        var edits = request.edits
        edits.cuts.append(TimelineCut(start: range.start, end: range.end, kind: .manual, source: .user))
        let timeMap = TimelineTimeMap(
            takeDuration: CMTime(seconds: request.takeDuration, preferredTimescale: 600), cuts: edits.cuts
        )
        guard timeMap.outputDuration.seconds >= 0.1 else { return nil }
        let previousMap = TimelineTimeMap(
            takeDuration: timeMap.takeDuration, cuts: request.edits.cuts
        )
        guard timeMap.outputDuration < previousMap.outputDuration else { return nil }
        return edits
    }

    static func restoring(_ request: CutRequest) -> TimelineEdits? {
        guard
            let range = resolve(
                .init(
                    anchor: request.range.start, head: request.range.end, duration: request.takeDuration
                )), range.canCut
        else { return nil }
        var edits = request.edits
        edits.cuts = edits.cuts.flatMap { cut -> [TimelineCut] in
            guard cut.isEnabled, cut.start < range.end, cut.end > range.start else { return [cut] }
            var pieces: [TimelineCut] = []
            if cut.start < range.start {
                var before = cut
                before.end = range.start
                pieces.append(before)
            }
            pieces.append(
                TimelineCut(
                    id: pieces.isEmpty ? cut.id : UUID(),
                    start: max(cut.start, range.start), end: min(cut.end, range.end),
                    kind: cut.kind, source: cut.source, isEnabled: false
                ))
            if cut.end > range.end {
                pieces.append(
                    TimelineCut(
                        start: range.end, end: cut.end, kind: cut.kind, source: cut.source
                    ))
            }
            return pieces
        }
        return edits == request.edits ? nil : edits
    }
}
