import CoreGraphics
import Foundation

/// Timeline times, in display seconds, that a dragged item's edges stick to.
struct EditorTimelineSnapTargets: Equatable {
    static let distance: CGFloat = 8

    let times: [Double]

    init(_ times: [Double]) {
        var unique: [Double] = []
        for time in times.filter(\.isFinite).sorted() where unique.last.map({ time - $0 > 1e-6 }) ?? true {
            unique.append(time)
        }
        self.times = unique
    }

    struct Query {
        let time: Double
        let tolerance: Double
    }

    func nearest(_ query: Query) -> Double? {
        guard query.time.isFinite, query.tolerance > 0, !times.isEmpty else { return nil }
        var lower = 0
        var upper = times.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if times[middle] < query.time { lower = middle + 1 } else { upper = middle }
        }
        let closest = [lower - 1, lower].filter(times.indices.contains).map { times[$0] }
            .min { abs($0 - query.time) < abs($1 - query.time) }
        guard let closest, abs(closest - query.time) <= query.tolerance else { return nil }
        return closest
    }
}

extension EditorTimelineView {
    /// Cuts and clip edges, scenes, chapters, transcript sentences, other items, the playhead and both ends.
    func snapTargets(excluding id: EditorPlacedItem.ID) -> EditorTimelineSnapTargets {
        var times = [0, projection.duration, projection.displayTime(playback.currentTime)]
        for clip in clipLayout.clips {
            times += [clip.start, clip.end]
        }
        times += sceneEvents.map { projection.displayTime($0.time) }
        for chapter in timelineChapters {
            times.append(projection.displayTime(chapter.time))
            if let end = chapter.endTime { times.append(projection.displayTime(end)) }
        }
        for segment in transcript?.segments ?? [] {
            times += [projection.displayTime(segment.startTime), projection.displayTime(segment.endTime)]
        }
        for item in placedTracks.flatMap(\.items) where item.id != id && item.canChangeTiming {
            times += [projection.displayTime(item.timing.start), projection.displayTime(item.timing.end)]
        }
        return .init(times)
    }
}
