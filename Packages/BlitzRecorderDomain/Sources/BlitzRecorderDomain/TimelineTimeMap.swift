import Foundation

public struct TimelineMediaInsertion: Equatable, Sendable {
    public let sourceStart: MediaTime
    public let compositionStart: MediaTime
    public let duration: MediaTime

    public init(sourceStart: MediaTime, compositionStart: MediaTime, duration: MediaTime) {
        self.sourceStart = sourceStart
        self.compositionStart = compositionStart
        self.duration = duration
    }
}

public struct TimelineMediaInsertionRequest: Sendable {
    public let activeTakeStart: MediaTime
    public let sourceTimeAtActiveStart: MediaTime
    public let sourceEnd: MediaTime

    public init(activeTakeStart: MediaTime, sourceTimeAtActiveStart: MediaTime, sourceEnd: MediaTime) {
        self.activeTakeStart = activeTakeStart
        self.sourceTimeAtActiveStart = sourceTimeAtActiveStart
        self.sourceEnd = sourceEnd
    }
}

public struct TimelineTimeMap: Equatable, Sendable {
    public static let timescale: Int32 = MediaTime.timescale

    public struct KeptRange: Equatable, Sendable {
        public let takeStart: MediaTime
        public let takeEnd: MediaTime
        public let outputStart: MediaTime

        public var duration: MediaTime {
            takeEnd - takeStart
        }

        public var outputEnd: MediaTime {
            outputStart + duration
        }
    }

    public struct RemovedRange: Equatable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let cutIDs: [UUID]

        public var duration: TimeInterval {
            max(0, end - start)
        }
    }

    public struct Seam: Equatable, Sendable {
        public let outputTime: TimeInterval
        public let takeStart: TimeInterval
        public let takeEnd: TimeInterval
        public let cutIDs: [UUID]

        public var removedDuration: TimeInterval {
            max(0, takeEnd - takeStart)
        }
    }

    public let takeDuration: MediaTime
    public let keptRanges: [KeptRange]
    public let removedRanges: [RemovedRange]

    public init(takeDuration: MediaTime, cuts: [TimelineCut]) {
        let normalizedDuration = MediaTime.maximum(.zero, takeDuration)
        self.takeDuration = normalizedDuration
        let durationSeconds = normalizedDuration.seconds

        var removed: [RemovedRange] = []
        let epsilon = 1.0 / Double(Self.timescale)
        let candidates = cuts
            .filter { $0.isEnabled && $0.start.isFinite && $0.end.isFinite }
            .map { cut -> (start: TimeInterval, end: TimeInterval, id: UUID) in
                let start = min(max(0, cut.start), durationSeconds)
                let end = min(max(start, cut.end), durationSeconds)
                return (start, end, cut.id)
            }
            .filter { $0.end - $0.start > epsilon }
            .sorted { $0.start < $1.start }
        for candidate in candidates {
            if let last = removed.last, candidate.start <= last.end + epsilon {
                removed[removed.count - 1] = RemovedRange(
                    start: last.start,
                    end: max(last.end, candidate.end),
                    cutIDs: last.cutIDs + [candidate.id]
                )
            } else {
                removed.append(RemovedRange(start: candidate.start, end: candidate.end, cutIDs: [candidate.id]))
            }
        }
        self.removedRanges = removed

        var kept: [KeptRange] = []
        var cursor = MediaTime.zero
        var outputCursor = MediaTime.zero
        for range in removed {
            let removedStart = MediaTime(seconds: range.start)
            let removedEnd = MediaTime(seconds: range.end)
            if removedStart > cursor {
                let keptRange = KeptRange(takeStart: cursor, takeEnd: removedStart, outputStart: outputCursor)
                kept.append(keptRange)
                outputCursor = keptRange.outputEnd
            }
            cursor = MediaTime.maximum(cursor, removedEnd)
        }
        if normalizedDuration > cursor {
            kept.append(KeptRange(takeStart: cursor, takeEnd: normalizedDuration, outputStart: outputCursor))
        }
        self.keptRanges = kept
    }

    public static func identity(takeDuration: MediaTime) -> TimelineTimeMap {
        TimelineTimeMap(takeDuration: takeDuration, cuts: [])
    }

    public var outputDuration: MediaTime {
        keptRanges.last?.outputEnd ?? .zero
    }

    public var hasCuts: Bool {
        !removedRanges.isEmpty
    }

    public var removedDuration: TimeInterval {
        removedRanges.reduce(0) { $0 + $1.duration }
    }

    public var seams: [Seam] {
        removedRanges.map { range in
            Seam(
                outputTime: outputSeconds(forTakeSeconds: range.start),
                takeStart: range.start,
                takeEnd: range.end,
                cutIDs: range.cutIDs
            )
        }
    }

    public func outputTime(forTake takeTime: MediaTime) -> MediaTime {
        var lower = 0
        var upper = keptRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if takeTime < keptRanges[middle].takeEnd {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        guard lower < keptRanges.count else { return outputDuration }
        let range = keptRanges[lower]
        guard takeTime >= range.takeStart else { return range.outputStart }
        return range.outputStart + (takeTime - range.takeStart)
    }

    public func outputSeconds(forTakeSeconds seconds: TimeInterval) -> TimeInterval {
        outputTime(forTake: MediaTime(seconds: seconds)).seconds
    }

    public func takeTime(forOutput outputTime: MediaTime) -> MediaTime {
        let index = outputRangeIndex(at: outputTime)
        guard index < keptRanges.count else { return keptRanges.last?.takeEnd ?? takeDuration }
        let range = keptRanges[index]
        let offset = MediaTime.maximum(.zero, outputTime - range.outputStart)
        return range.takeStart + offset
    }

    public func takeSeconds(forOutputSeconds seconds: TimeInterval) -> TimeInterval {
        takeTime(forOutput: MediaTime(seconds: seconds)).seconds
    }

    public func isRemoved(takeTime seconds: TimeInterval) -> Bool {
        removedRange(containing: seconds) != nil
    }

    public func removedRange(containing seconds: TimeInterval) -> RemovedRange? {
        guard seconds.isFinite else { return nil }
        var lower = 0
        var upper = removedRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if seconds < removedRanges[middle].end {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        guard lower < removedRanges.count, seconds >= removedRanges[lower].start else { return nil }
        return removedRanges[lower]
    }

    public func keptRange(containingOutput outputTime: MediaTime) -> KeptRange? {
        let index = outputRangeIndex(at: outputTime)
        guard index < keptRanges.count, outputTime >= keptRanges[index].outputStart else { return nil }
        return keptRanges[index]
    }

    private func outputRangeIndex(at time: MediaTime) -> Int {
        var lower = 0
        var upper = keptRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if time < keptRanges[middle].outputEnd {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower
    }

    public var keptRangesHNS: [(takeStart: Int64, takeEnd: Int64)] {
        keptRanges.map { ($0.takeStart.hundredNanoseconds, $0.takeEnd.hundredNanoseconds) }
    }

    public func mediaInsertions(_ request: TimelineMediaInsertionRequest) -> [TimelineMediaInsertion] {
        let activeStart = request.activeTakeStart
        let sourceAtActiveStart = request.sourceTimeAtActiveStart
        let sourceEnd = request.sourceEnd
        let availableSource = sourceEnd - sourceAtActiveStart
        guard availableSource > .zero else { return [] }
        let activeEnd = activeStart + availableSource

        var insertions: [TimelineMediaInsertion] = []
        for range in keptRanges {
            let pieceStart = MediaTime.maximum(range.takeStart, activeStart)
            let pieceEnd = MediaTime.minimum(range.takeEnd, activeEnd)
            guard pieceEnd > pieceStart else { continue }
            let sourceStart = sourceAtActiveStart + (pieceStart - activeStart)
            let compositionStart = range.outputStart + (pieceStart - range.takeStart)
            insertions.append(TimelineMediaInsertion(
                sourceStart: sourceStart,
                compositionStart: compositionStart,
                duration: pieceEnd - pieceStart
            ))
        }
        return insertions
    }
}
