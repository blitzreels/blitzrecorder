import CoreMedia

struct RecordingSceneSegment: Equatable {
    let timeRange: CMTimeRange
    let scene: RecordingScene

    static func == (lhs: RecordingSceneSegment, rhs: RecordingSceneSegment) -> Bool {
        CMTimeRangeEqual(lhs.timeRange, rhs.timeRange) && lhs.scene == rhs.scene
    }
}

enum RecordingSceneTimeline {
    static func segments(
        sceneEvents: [RecordingSceneEvent],
        fallbackScene: RecordingScene,
        duration: CMTime,
        sourceTimeRanges: [CMTimeRange] = []
    ) -> [RecordingSceneSegment] {
        var boundaries = [.zero, duration].filter { $0.isValid && CMTimeCompare($0, .zero) >= 0 }
        boundaries.append(contentsOf: sceneEvents
            .map(\.time)
            .filter { $0.isFinite }
            .map { CMTime(seconds: min(max(0, $0), max(0, duration.seconds)), preferredTimescale: 600) })

        for sourceTimeRange in sourceTimeRanges {
            boundaries.append(sourceTimeRange.start)
            boundaries.append(CMTimeRangeGetEnd(sourceTimeRange))
        }

        let uniqueBoundaries = sortedUniqueBoundaries(boundaries, duration: duration)
        let sortedEvents = sceneEvents
            .filter { $0.time.isFinite }
            .sorted { $0.time < $1.time }

        var segments: [RecordingSceneSegment] = []
        for index in 0..<(uniqueBoundaries.count - 1) {
            let start = uniqueBoundaries[index]
            let end = uniqueBoundaries[index + 1]
            guard CMTimeCompare(end, start) > 0 else { continue }
            let scene = sortedEvents.last(where: { $0.time <= start.seconds })?.scene ?? fallbackScene
            segments.append(RecordingSceneSegment(
                timeRange: CMTimeRange(start: start, duration: CMTimeSubtract(end, start)),
                scene: scene
            ))
        }

        if segments.isEmpty {
            return [RecordingSceneSegment(timeRange: CMTimeRange(start: .zero, duration: duration), scene: fallbackScene)]
        }
        return segments
    }

    static func requiresCanvasAwareRendering(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> Bool {
        if RecordingScene(settings: settings).requiresCanvasAwareRendering {
            return true
        }
        return sceneEvents.contains { $0.scene.requiresCanvasAwareRendering }
    }

    private static func sortedUniqueBoundaries(_ boundaries: [CMTime], duration: CMTime) -> [CMTime] {
        let sortedBoundaries = boundaries
            .filter { $0.isValid && $0.isNumeric }
            .map { CMTimeMaximum(.zero, CMTimeMinimum($0, duration)) }
            .sorted { CMTimeCompare($0, $1) < 0 }

        var uniqueBoundaries: [CMTime] = []
        for boundary in sortedBoundaries where uniqueBoundaries.last.map({ CMTimeCompare($0, boundary) != 0 }) ?? true {
            uniqueBoundaries.append(boundary)
        }
        return uniqueBoundaries
    }
}

extension RecordingScene {
    var requiresCanvasAwareRendering: Bool {
        canvasPadding > 0.001 || canvasBackgroundStyle != .black
    }
}
