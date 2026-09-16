import CoreMedia
import Foundation

enum EditorTimelineIndex {
    static func eventIndex(at time: Double, in events: [RecordingSceneEvent]) -> Int {
        guard !events.isEmpty else { return 0 }
        let cutoff = time + 0.0001
        var low = 0
        var high = events.count - 1
        var index = 0
        while low <= high {
            let mid = (low + high) / 2
            if events[mid].time <= cutoff {
                index = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return index
    }

    static func previousBoundary(at time: Double, in times: [Double], slack: Double = 0.25) -> Double {
        let cutoff = time - slack
        var low = 0
        var high = times.count - 1
        var index: Int?
        while low <= high {
            let mid = (low + high) / 2
            if times[mid] < cutoff {
                index = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return index.map { times[$0] } ?? 0
    }

    static func nextBoundary(
        at time: Double,
        in times: [Double],
        duration: Double,
        slack: Double = 0.25
    ) -> Double {
        let cutoff = time + slack
        var low = 0
        var high = times.count - 1
        var index: Int?
        while low <= high {
            let mid = (low + high) / 2
            if times[mid] > cutoff {
                index = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return index.map { times[$0] } ?? duration
    }

    static func containingSegmentIndex(at time: CMTime, in segments: [FinalExportRenderSegment]) -> Int? {
        guard !segments.isEmpty else { return nil }
        var low = 0
        var high = segments.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = segments[mid].timeRange
            if CMTimeRangeContainsTime(range, time: time) {
                return mid
            }
            if CMTimeCompare(time, range.start) < 0 {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return nil
    }

    static func segmentIndex(at time: CMTime, in segments: [FinalExportRenderSegment]) -> Int? {
        containingSegmentIndex(at: time, in: segments) ?? (segments.isEmpty ? nil : segments.count - 1)
    }
}
