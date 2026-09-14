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
        let projection = EditorTimelineProjection(.init(duration: request.duration, cuts: request.edits.cuts))
        let layout = EditorVideoClipLayout(.init(projection: projection, splits: request.edits.videoSplits))
        return layout.clip(at: projection.displayTime(TimelineTimeMap.time(request.time).seconds))?.range
    }
}
