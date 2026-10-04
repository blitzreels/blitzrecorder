import Foundation

enum EditorClipSpine {
    struct Request: Equatable {
        let edits: TimelineEdits
        let duration: Double
        var silenceCuts: [TimelineCut] = []
        var sceneEventTimes: [Double] = []
    }

    struct BladeRequest {
        let edits: TimelineEdits
        let time: Double
        let duration: Double
        var silenceCuts: [TimelineCut] = []
    }

    struct ExtendRequest {
        let edits: TimelineEdits
        let clip: EditorTimeRange
        let nextClipStart: Double?
        let duration: Double
        var delta: Double = 0
    }

    struct LeftEdgeRequest {
        let edits: TimelineEdits
        let clip: EditorTimeRange
        let previousClipEnd: Double?
        let duration: Double
        let delta: Double
    }

    static func dragLeft(_ request: LeftEdgeRequest) -> DragRightResult {
        let unchanged = DragRightResult(edits: nil, selection: request.clip)
        guard request.delta.isFinite, request.duration.isFinite,
            request.clip.start >= 0, request.clip.end <= request.duration,
            request.clip.end > request.clip.start,
            request.previousClipEnd?.isFinite != false,
            (request.previousClipEnd ?? 0) <= request.clip.start else { return unchanged }
        let start = TimelineTimeMap.time(request.clip.start).seconds
        let limit = TimelineTimeMap.time(max(0, request.previousClipEnd ?? 0)).seconds
        let newStart = TimelineTimeMap.time(min(max(limit, start + request.delta),
            max(start, request.clip.end - 0.1))).seconds
        if newStart > start {
            guard let edits = EditorTimeRange.removing(.init(
                range: .init(start: start, end: newStart), edits: request.edits, takeDuration: request.duration
            )) else { return unchanged }
            return .init(edits: edits, selection: .init(start: newStart, end: request.clip.end))
        }
        guard newStart < start, var edits = EditorTimeRange.restoring(.init(
            range: .init(start: newStart, end: start), edits: request.edits, takeDuration: request.duration
        )) else { return unchanged }
        edits.videoSplits = edits.videoSplits.filter { $0.isFinite && ($0 <= newStart || $0 > start) }
        if request.previousClipEnd != nil, newStart == limit,
            !edits.videoSplits.contains(where: { TimelineTimeMap.time($0).seconds == newStart }) {
            edits.videoSplits.append(newStart)
            edits.videoSplits.sort()
        }
        return .init(edits: edits, selection: .init(start: newStart, end: request.clip.end))
    }

    static func layout(_ request: Request) -> EditorVideoClipLayout {
        let projection = EditorTimelineProjection(.init(duration: request.duration, cuts: request.edits.cuts))
        return EditorVideoClipLayout(.init(projection: projection, splits: boundaries(request)))
    }

    private static let seekTimesLock = NSLock()
    private static var cachedSeekTimes: (Request, [Double])?

    static func seekTimes(_ request: Request) -> [Double] {
        seekTimesLock.lock()
        if let cachedSeekTimes, cachedSeekTimes.0 == request {
            let times = cachedSeekTimes.1
            seekTimesLock.unlock()
            return times
        }
        seekTimesLock.unlock()

        var times = (boundaries(request) + request.sceneEventTimes)
            .filter(\.isFinite)
            .map { TimelineTimeMap.time($0).seconds }
        times.sort()
        var unique: [Double] = []
        unique.reserveCapacity(times.count)
        for time in times where unique.last != time {
            unique.append(time)
        }

        seekTimesLock.lock()
        cachedSeekTimes = (request, unique)
        seekTimesLock.unlock()
        return unique
    }

    static func boundaries(_ request: Request) -> [Double] {
        let restored = request.edits.cuts.filter {
            !$0.isEnabled && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
        }.sorted { $0.start < $1.start }
        var times: [Double] = []
        for cut in request.silenceCuts where cut.kind == .silence && cut.isEnabled
            && cut.start.isFinite && cut.end.isFinite && cut.end > cut.start
        {
            times.append(contentsOf: [cut.start, cut.end])
        }
        times.sort()
        var restoredIndex = 0
        let automatic = times.filter { time in
            while restoredIndex < restored.count, restored[restoredIndex].end <= time {
                restoredIndex += 1
            }
            return restoredIndex == restored.count || restored[restoredIndex].start > time
        }
        return (request.edits.videoSplits.filter(\.isFinite) + automatic).sorted()
    }

    static func splitting(_ request: BladeRequest) -> TimelineEdits? {
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

    static func range(_ request: BladeRequest) -> EditorTimeRange? {
        guard request.time.isFinite, request.duration.isFinite, request.duration > 0 else { return nil }
        let layout = Self.layout(.init(
            edits: request.edits, duration: request.duration, silenceCuts: request.silenceCuts
        ))
        let displayTime = EditorTimelineProjection(.init(duration: request.duration, cuts: request.edits.cuts))
            .displayTime(TimelineTimeMap.time(request.time).seconds)
        return layout.clip(at: displayTime)?.range
    }

    private static func validRightEdge(_ request: ExtendRequest) -> Bool {
        request.clip.start.isFinite && request.clip.end.isFinite
            && request.clip.start >= 0 && request.clip.end > request.clip.start
            && request.duration.isFinite && request.duration >= request.clip.end
            && request.nextClipStart?.isFinite != false
            && (request.nextClipStart ?? request.duration) >= request.clip.end
    }

    private static func minimumRightEnd(_ request: ExtendRequest) -> Double {
        min(TimelineTimeMap.time(request.clip.end).seconds,
            TimelineTimeMap.time(request.clip.start + 0.1).seconds)
    }

    static func canTrimRight(_ request: ExtendRequest) -> Bool {
        guard validRightEdge(request) else { return false }
        return TimelineTimeMap.time(request.clip.end).seconds > minimumRightEnd(request)
            || rightExpandLimit(request) != nil
    }

    static func rightExpandLimit(_ request: ExtendRequest) -> Double? {
        guard validRightEdge(request) else { return nil }
        let clipEnd = TimelineTimeMap.time(request.clip.end).seconds
        let limit = TimelineTimeMap.time(min(request.duration, request.nextClipStart ?? request.duration)).seconds
        guard limit > clipEnd else { return nil }
        guard request.edits.enabledCuts.contains(where: { $0.start < limit && $0.end > clipEnd }) else { return nil }
        return limit
    }

    struct DragRightResult: Equatable {
        let edits: TimelineEdits?
        let selection: EditorTimeRange
    }

    static func dragRight(_ request: ExtendRequest) -> DragRightResult {
        let unchanged = DragRightResult(edits: nil, selection: request.clip)
        guard request.delta.isFinite, validRightEdge(request) else { return unchanged }
        let clipEnd = TimelineTimeMap.time(request.clip.end).seconds
        if request.delta < 0 {
            let newEnd = TimelineTimeMap.time(max(minimumRightEnd(request), clipEnd + request.delta)).seconds
            guard newEnd < clipEnd,
                let edits = EditorTimeRange.removing(.init(
                    range: .init(start: newEnd, end: clipEnd), edits: request.edits, takeDuration: request.duration
                )) else { return unchanged }
            return .init(edits: edits, selection: .init(start: request.clip.start, end: newEnd))
        }
        guard let edits = extendingRight(request), let limit = rightExpandLimit(request) else { return unchanged }
        let newEnd = TimelineTimeMap.time(min(limit, clipEnd + request.delta)).seconds
        return .init(edits: edits, selection: .init(start: request.clip.start, end: newEnd))
    }

    static func extendingRight(_ request: ExtendRequest) -> TimelineEdits? {
        guard let limit = rightExpandLimit(request), request.delta.isFinite else { return nil }
        let clipEnd = TimelineTimeMap.time(request.clip.end).seconds
        let newEnd = TimelineTimeMap.time(min(limit, clipEnd + max(0, request.delta))).seconds
        guard newEnd > clipEnd else { return nil }
        guard var edits = EditorTimeRange.restoring(.init(
            range: .init(start: clipEnd, end: newEnd), edits: request.edits, takeDuration: request.duration
        )) else { return nil }
        edits.videoSplits = edits.videoSplits.filter { split in
            guard split.isFinite else { return false }
            let time = TimelineTimeMap.time(split).seconds
            return time < clipEnd || time >= newEnd
        }
        if let nextClipStart = request.nextClipStart,
            newEnd == TimelineTimeMap.time(nextClipStart).seconds,
            !edits.videoSplits.contains(where: { TimelineTimeMap.time($0).seconds == newEnd }) {
            edits.videoSplits.append(newEnd)
            edits.videoSplits.sort()
        }
        return edits == request.edits ? nil : edits
    }
}
