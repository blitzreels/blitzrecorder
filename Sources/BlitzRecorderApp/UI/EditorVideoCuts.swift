import Foundation

enum EditorVideoCuts {
    struct Request {
        let edits: TimelineEdits
        let time: Double
        let duration: Double
    }

    static func splitting(_ request: Request) -> TimelineEdits? {
        guard request.time.isFinite, request.duration.isFinite,
            request.time > 0.05, request.time < request.duration - 0.05 else { return nil }
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(request.duration), cuts: request.edits.cuts)
        guard !map.isRemoved(takeTime: request.time) else { return nil }
        var edits = request.edits
        guard !edits.videoSplits.contains(where: { abs($0 - request.time) <= 1.0 / 600 }) else { return edits }
        edits.videoSplits.append(request.time)
        edits.videoSplits.sort()
        return edits
    }

    static func range(_ request: Request) -> EditorTimeRange? {
        guard request.time.isFinite, request.duration.isFinite, request.duration > 0 else { return nil }
        let boundaries = ([0] + request.edits.videoSplits.filter {
            $0.isFinite && $0 > 0 && $0 < request.duration
        } + request.edits.enabledCuts.flatMap { [$0.start, $0.end] } + [request.duration]).sorted()
        let start = boundaries.last { $0 <= request.time } ?? 0
        let end = boundaries.first { $0 > request.time } ?? request.duration
        guard end > start else { return nil }
        return EditorTimeRange(start: start, end: end)
    }
}
