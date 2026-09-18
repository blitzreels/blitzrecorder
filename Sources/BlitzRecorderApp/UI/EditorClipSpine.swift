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
        let restored = request.edits.cuts.filter { !$0.isEnabled }
        func isRestoredInterior(_ time: Double) -> Bool {
            restored.contains { time >= $0.start && time < $0.end }
        }
        var times = request.edits.videoSplits.filter { $0.isFinite && !isRestoredInterior($0) }
        for cut in request.silenceCuts where cut.kind == .silence && cut.isEnabled
            && cut.start.isFinite && cut.end.isFinite && cut.end > cut.start
        {
            for time in [cut.start, cut.end] where !isRestoredInterior(time) {
                times.append(time)
            }
        }
        return times
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

    static func rightExpandLimit(_ request: ExtendRequest) -> Double? {
        guard request.clip.end.isFinite, request.duration.isFinite, request.duration > 0 else { return nil }
        let clipEnd = TimelineTimeMap.time(request.clip.end).seconds
        let limit = TimelineTimeMap.time(min(request.duration, request.nextClipStart ?? request.duration)).seconds
        guard limit - clipEnd >= 1.0 / 600 else { return nil }
        guard request.edits.enabledCuts.contains(where: { $0.start < limit && $0.end > clipEnd }) else { return nil }
        return limit
    }

    struct DragRightResult: Equatable {
        let edits: TimelineEdits?
        let selection: EditorTimeRange
    }

    static func dragRight(_ request: ExtendRequest) -> DragRightResult {
        let clipEnd = TimelineTimeMap.time(request.clip.end).seconds
        let newEnd = rightExpandLimit(request).map {
            TimelineTimeMap.time(min($0, clipEnd + max(0, request.delta))).seconds
        } ?? clipEnd
        return DragRightResult(
            edits: extendingRight(.init(
                edits: request.edits, clip: request.clip, nextClipStart: request.nextClipStart,
                duration: request.duration, delta: request.delta
            )),
            selection: .init(start: request.clip.start, end: max(clipEnd, newEnd))
        )
    }

    static func extendingRight(_ request: ExtendRequest) -> TimelineEdits? {
        guard let limit = rightExpandLimit(request), request.delta.isFinite else { return nil }
        let clipEnd = TimelineTimeMap.time(request.clip.end).seconds
        let newEnd = TimelineTimeMap.time(min(limit, clipEnd + max(0, request.delta))).seconds
        guard newEnd - clipEnd >= 1.0 / 600 else { return nil }
        guard var edits = EditorTimeRange.restoring(.init(
            range: .init(start: clipEnd, end: newEnd), edits: request.edits, takeDuration: request.duration
        )) else { return nil }
        edits.videoSplits = edits.videoSplits.filter { split in
            guard split.isFinite else { return false }
            let time = TimelineTimeMap.time(split).seconds
            return time < clipEnd || time >= newEnd
        }
        return edits == request.edits ? nil : edits
    }
}
