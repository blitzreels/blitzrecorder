import CoreGraphics
import CoreMedia

enum FinalExportEngine: Equatable {
    case assetExportSession
    case optimizedWriter
}

struct FinalExportSourceInput: Equatable {
    let kind: SceneLayerKind
    let duration: CMTime
    let timelineOffset: CMTime
    let sourceStartOffset: CMTime

    init(
        kind: SceneLayerKind,
        duration: CMTime,
        timelineOffset: CMTime,
        sourceStartOffset: CMTime = .zero
    ) {
        self.kind = kind
        self.duration = duration
        self.timelineOffset = timelineOffset
        self.sourceStartOffset = sourceStartOffset
    }
}

struct FinalExportSourceInsertion: Equatable {
    let kind: SceneLayerKind
    let sourceStart: CMTime
    let compositionStart: CMTime
    let duration: CMTime

    static func == (lhs: FinalExportSourceInsertion, rhs: FinalExportSourceInsertion) -> Bool {
        lhs.kind == rhs.kind
            && CMTimeCompare(lhs.sourceStart, rhs.sourceStart) == 0
            && CMTimeCompare(lhs.compositionStart, rhs.compositionStart) == 0
            && CMTimeCompare(lhs.duration, rhs.duration) == 0
    }

    var timeRange: CMTimeRange {
        CMTimeRange(start: compositionStart, duration: duration)
    }

    func isActive(at time: CMTime) -> Bool {
        CMTimeCompare(time, compositionStart) >= 0
            && CMTimeCompare(time, CMTimeRangeGetEnd(timeRange)) < 0
    }
}

struct FinalExportRenderSegment: Equatable {
    let timeRange: CMTimeRange
    let scene: RecordingScene
    let activeLayerOrder: [SceneLayerKind]

    static func == (lhs: FinalExportRenderSegment, rhs: FinalExportRenderSegment) -> Bool {
        CMTimeRangeEqual(lhs.timeRange, rhs.timeRange)
            && lhs.scene == rhs.scene
            && lhs.activeLayerOrder == rhs.activeLayerOrder
    }
}

struct FinalExportPlan: Equatable {
    let duration: CMTime
    let renderSize: CGSize
    let engine: FinalExportEngine
    let sourceInsertions: [FinalExportSourceInsertion]
    let renderSegments: [FinalExportRenderSegment]

    static func == (lhs: FinalExportPlan, rhs: FinalExportPlan) -> Bool {
        CMTimeCompare(lhs.duration, rhs.duration) == 0
            && lhs.renderSize == rhs.renderSize
            && lhs.engine == rhs.engine
            && lhs.sourceInsertions == rhs.sourceInsertions
            && lhs.renderSegments == rhs.renderSegments
    }

    func insertion(for kind: SceneLayerKind) -> FinalExportSourceInsertion? {
        sourceInsertions.first { $0.kind == kind }
    }
}

enum FinalExportPlanning {
    static func plan(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        sources: [FinalExportSourceInput]
    ) throws -> FinalExportPlan {
        guard !sources.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let durationSources = visibleTimelineSources(sources, settings: settings, sceneEvents: sceneEvents)
        guard !durationSources.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let duration = durationSources
            .map { CMTimeAdd($0.timelineOffset, $0.duration) }
            .reduce(CMTimeAdd(durationSources[0].timelineOffset, durationSources[0].duration)) { CMTimeMinimum($0, $1) }
        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let sourceInsertions: [FinalExportSourceInsertion] = durationSources.compactMap { source in
            let insertion = sourceInsertion(for: source, compositionDuration: duration)
            guard CMTimeCompare(insertion.duration, .zero) > 0 else { return nil }
            return insertion
        }

        return FinalExportPlan(
            duration: duration,
            renderSize: renderSize,
            engine: engine(settings: settings, sceneEvents: sceneEvents),
            sourceInsertions: sourceInsertions,
            renderSegments: renderSegments(
                settings: settings,
                sceneEvents: sceneEvents,
                duration: duration,
                renderSize: renderSize,
                sourceInsertions: sourceInsertions,
                transitionSampleInterval: transitionSampleInterval(for: settings)
            )
        )
    }

    static func sourceInsertion(
        for source: FinalExportSourceInput,
        compositionDuration: CMTime
    ) -> FinalExportSourceInsertion {
        let offset = source.timelineOffset
        let offsetSourceStart = CMTimeCompare(offset, .zero) < 0 ? CMTimeMultiplyByFloat64(offset, multiplier: -1) : .zero
        let sourceStart = CMTimeAdd(offsetSourceStart, source.sourceStartOffset)
        let compositionStart = CMTimeCompare(offset, .zero) > 0 ? offset : .zero
        let remainingCompositionDuration = CMTimeSubtract(compositionDuration, compositionStart)
        let remainingSourceDuration = CMTimeSubtract(source.duration, sourceStart)
        let duration = CMTimeMinimum(remainingCompositionDuration, remainingSourceDuration)
        return FinalExportSourceInsertion(
            kind: source.kind,
            sourceStart: sourceStart,
            compositionStart: compositionStart,
            duration: duration
        )
    }

    private static func visibleTimelineSources(
        _ sources: [FinalExportSourceInput],
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> [FinalExportSourceInput] {
        var visibleSources = RecordingScene(settings: settings).enabledSources
        for event in sceneEvents {
            visibleSources.formUnion(event.scene.enabledSources)
        }
        return sources.filter { visibleSources.contains($0.kind.source) }
    }

    private static func renderSegments(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        duration: CMTime,
        renderSize: CGSize,
        sourceInsertions: [FinalExportSourceInsertion],
        transitionSampleInterval: TimeInterval
    ) -> [FinalExportRenderSegment] {
        let fallbackScene = RecordingScene(settings: settings)
        let insertionByKind = Dictionary(uniqueKeysWithValues: sourceInsertions.map { ($0.kind, $0) })
        let segments = RecordingSceneTimeline.segments(
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene,
            duration: duration,
            sourceTimeRanges: sourceInsertions.map(\.timeRange),
            transitionSampleInterval: transitionSampleInterval
        )
        return segments.enumerated().map { index, segment in
            let endScene = segments.indices.contains(index + 1)
                ? segments[index + 1].scene
                : segment.scene
            let activeLayerOrder = activeLayerOrder(
                startScene: segment.scene,
                endScene: endScene,
                insertionByKind: insertionByKind,
                timeRange: segment.timeRange,
                renderSize: renderSize
            )
            return FinalExportRenderSegment(
                timeRange: segment.timeRange,
                scene: segment.scene,
                activeLayerOrder: activeLayerOrder
            )
        }
    }

    private static func activeLayerOrder(
        startScene: RecordingScene,
        endScene: RecordingScene,
        insertionByKind: [SceneLayerKind: FinalExportSourceInsertion],
        timeRange: CMTimeRange,
        renderSize: CGSize
    ) -> [SceneLayerKind] {
        let canvas = CGRect(origin: .zero, size: renderSize)
        let startGeometry = SceneRenderGeometry(canvas: canvas, scene: startScene, origin: .upperLeft)
        let endGeometry = SceneRenderGeometry(canvas: canvas, scene: endScene, origin: .upperLeft)

        var orderedKinds = endGeometry.activeLayerOrder
        for kind in startGeometry.activeLayerOrder where !orderedKinds.contains(kind) {
            orderedKinds.append(kind)
        }
        return orderedKinds.filter { kind in
            insertionByKind[kind].map { sourceIsActive($0, during: timeRange) } ?? false
        }
    }

    private static func sourceIsActive(
        _ insertion: FinalExportSourceInsertion,
        during timeRange: CMTimeRange
    ) -> Bool {
        let intersection = CMTimeRangeGetIntersection(insertion.timeRange, otherRange: timeRange)
        return intersection.isValid && CMTimeCompare(intersection.duration, .zero) > 0
    }

    private static func engine(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> FinalExportEngine {
        RecordingSceneTimeline.requiresCanvasAwareRendering(settings: settings, sceneEvents: sceneEvents)
            ? .assetExportSession
            : .optimizedWriter
    }

    static func transitionSampleInterval(for settings: RecordingSettings) -> TimeInterval {
        1.0 / Double(max(15, min(240, settings.framesPerSecond)))
    }
}
