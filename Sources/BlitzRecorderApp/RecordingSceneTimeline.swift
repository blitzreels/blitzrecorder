import CoreMedia

struct RecordingSceneSegment: Equatable {
    let timeRange: CMTimeRange
    let scene: RecordingScene

    static func == (lhs: RecordingSceneSegment, rhs: RecordingSceneSegment) -> Bool {
        CMTimeRangeEqual(lhs.timeRange, rhs.timeRange) && lhs.scene == rhs.scene
    }
}

enum RecordingSceneTimeline {
    private static let defaultTransitionSampleInterval = 1.0 / 60.0

    static func segments(
        sceneEvents: [RecordingSceneEvent],
        fallbackScene: RecordingScene,
        duration: CMTime,
        sourceTimeRanges: [CMTimeRange] = [],
        transitionSampleInterval: TimeInterval = defaultTransitionSampleInterval
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
        boundaries.append(contentsOf: transitionBoundaries(
            sceneEvents: sceneEvents,
            duration: duration,
            transitionSampleInterval: transitionSampleInterval
        ))

        let uniqueBoundaries = sortedUniqueBoundaries(boundaries, duration: duration)

        var segments: [RecordingSceneSegment] = []
        for index in 0..<(uniqueBoundaries.count - 1) {
            let start = uniqueBoundaries[index]
            let end = uniqueBoundaries[index + 1]
            guard CMTimeCompare(end, start) > 0 else { continue }
            let scene = scene(
                at: start.seconds,
                sceneEvents: sceneEvents,
                fallbackScene: fallbackScene
            )
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

    static func scene(
        at time: TimeInterval,
        sceneEvents: [RecordingSceneEvent],
        fallbackScene: RecordingScene
    ) -> RecordingScene {
        let sortedEvents = sceneEvents
            .filter { $0.time.isFinite }
            .sorted { $0.time < $1.time }
        var currentScene = fallbackScene
        var activeTransition: (
            startTime: TimeInterval,
            transition: RecordingSceneTransition,
            startScene: RecordingScene,
            targetScene: RecordingScene
        )?
        for event in sortedEvents {
            guard event.time <= time else {
                break
            }

            if let transition = activeTransition {
                currentScene = resolvedScene(
                    for: transition,
                    at: event.time
                )
                if event.time >= transition.startTime + transition.transition.duration {
                    activeTransition = nil
                }
            }

            if event.transition.isCut {
                currentScene = event.scene
                activeTransition = nil
            } else {
                activeTransition = (
                    startTime: event.time,
                    transition: event.transition,
                    startScene: currentScene,
                    targetScene: event.scene
                )
            }
        }

        if let activeTransition {
            return resolvedScene(for: activeTransition, at: time)
        }
        return currentScene
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

    private static func transitionBoundaries(
        sceneEvents: [RecordingSceneEvent],
        duration: CMTime,
        transitionSampleInterval: TimeInterval
    ) -> [CMTime] {
        let durationSeconds = max(0, duration.seconds)
        let sampleInterval = max(1.0 / 240.0, min(1.0 / 15.0, transitionSampleInterval))
        var boundaries: [CMTime] = []
        for event in sceneEvents where event.time.isFinite && !event.transition.isCut {
            let start = min(max(0, event.time), durationSeconds)
            let end = min(start + event.transition.duration, durationSeconds)
            guard end > start else { continue }

            boundaries.append(CMTime(seconds: start, preferredTimescale: 600))
            var sampleTime = start + sampleInterval
            while sampleTime < end {
                boundaries.append(CMTime(seconds: sampleTime, preferredTimescale: 600))
                sampleTime += sampleInterval
            }
            boundaries.append(CMTime(seconds: end, preferredTimescale: 600))
        }
        return boundaries
    }

    private static func resolvedScene(
        for transition: (
            startTime: TimeInterval,
            transition: RecordingSceneTransition,
            startScene: RecordingScene,
            targetScene: RecordingScene
        ),
        at time: TimeInterval
    ) -> RecordingScene {
        let elapsed = time - transition.startTime
        guard elapsed >= 0,
              elapsed < transition.transition.duration else {
            return transition.targetScene
        }
        return transition.startScene.interpolated(
            to: transition.targetScene,
            progress: transition.transition.progress(elapsed: elapsed)
        )
    }
}

extension RecordingScene {
    var requiresCanvasAwareRendering: Bool {
        canvasPadding > 0.001 || canvasBackgroundStyle != .black || canvasBackgroundAnimated
    }
}
