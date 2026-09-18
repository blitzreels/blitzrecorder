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

    var activeTakeStart: CMTime {
        CMTimeCompare(timelineOffset, .zero) > 0 ? timelineOffset : .zero
    }

    var sourceTimeAtActiveStart: CMTime {
        let offsetSourceStart = CMTimeCompare(timelineOffset, .zero) < 0
            ? CMTimeMultiplyByFloat64(timelineOffset, multiplier: -1)
            : .zero
        return CMTimeAdd(offsetSourceStart, sourceStartOffset)
    }

    var activeTakeEnd: CMTime {
        CMTimeAdd(activeTakeStart, CMTimeSubtract(duration, sourceTimeAtActiveStart))
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
    let timeMap: TimelineTimeMap

    init(
        duration: CMTime,
        renderSize: CGSize,
        engine: FinalExportEngine,
        sourceInsertions: [FinalExportSourceInsertion],
        renderSegments: [FinalExportRenderSegment],
        timeMap: TimelineTimeMap? = nil
    ) {
        self.duration = duration
        self.renderSize = renderSize
        self.engine = engine
        self.sourceInsertions = sourceInsertions
        self.renderSegments = renderSegments
        self.timeMap = timeMap ?? .identity(takeDuration: duration)
    }

    static func == (lhs: FinalExportPlan, rhs: FinalExportPlan) -> Bool {
        CMTimeCompare(lhs.duration, rhs.duration) == 0
            && lhs.renderSize == rhs.renderSize
            && lhs.engine == rhs.engine
            && lhs.sourceInsertions == rhs.sourceInsertions
            && lhs.renderSegments == rhs.renderSegments
            && lhs.timeMap == rhs.timeMap
    }

    var takeDuration: CMTime {
        timeMap.takeDuration.cmTime
    }

    func insertion(for kind: SceneLayerKind) -> FinalExportSourceInsertion? {
        sourceInsertions.first { $0.kind == kind }
    }

    func insertions(for kind: SceneLayerKind) -> [FinalExportSourceInsertion] {
        sourceInsertions.filter { $0.kind == kind }
    }
}

enum FinalExportPlanning {
    struct TimelineTrimRequest {
        let sources: [FinalExportSourceInput]
        let offset: CMTime
    }

    struct PlanRequest {
        let settings: RecordingSettings
        let sceneEvents: [RecordingSceneEvent]
        let sources: [FinalExportSourceInput]
        let cuts: [TimelineCut]
    }

    static func applyingTimelineTrim(_ request: TimelineTrimRequest) -> [FinalExportSourceInput] {
        guard request.offset.isValid,
              request.offset.seconds.isFinite,
              CMTimeCompare(request.offset, .zero) > 0 else {
            return request.sources
        }
        let offset = CMTimeConvertScale(
            request.offset,
            timescale: 600,
            method: .roundHalfAwayFromZero
        )
        return request.sources.map { source in
            FinalExportSourceInput(
                kind: source.kind,
                duration: source.duration,
                timelineOffset: CMTimeSubtract(source.timelineOffset, offset),
                sourceStartOffset: source.sourceStartOffset
            )
        }
    }

    static func plan(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent],
        sources: [FinalExportSourceInput],
        cuts: [TimelineCut] = []
    ) throws -> FinalExportPlan {
        try plan(PlanRequest(settings: settings, sceneEvents: sceneEvents, sources: sources, cuts: cuts))
    }

    static func plan(_ request: PlanRequest) throws -> FinalExportPlan {
        let settings = request.settings
        let sceneEvents = request.sceneEvents
        guard !request.sources.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let durationSources = visibleTimelineSources(request.sources, settings: settings, sceneEvents: sceneEvents)
        guard !durationSources.isEmpty else {
            throw RecorderError.exportUnavailable
        }

        let takeDuration = durationSources
            .map { CMTimeAdd($0.timelineOffset, $0.duration) }
            .reduce(CMTimeAdd(durationSources[0].timelineOffset, durationSources[0].duration)) { CMTimeMinimum($0, $1) }
        let timeMap = TimelineTimeMap(takeDuration: takeDuration, cuts: request.cuts)
        let duration = timeMap.outputDuration.cmTime
        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let insertions = durationSources.flatMap { source in
            Self.sourceInsertions(for: source, timeMap: timeMap)
        }

        return FinalExportPlan(
            duration: duration,
            renderSize: renderSize,
            engine: engine(settings: settings, sceneEvents: sceneEvents),
            sourceInsertions: insertions,
            renderSegments: renderSegments(RenderSegmentRequest(
                settings: settings,
                sceneEvents: sceneEvents,
                timeMap: timeMap,
                renderSize: renderSize,
                sources: durationSources,
                sourceInsertions: insertions,
                transitionSampleInterval: transitionSampleInterval(for: settings)
            )),
            timeMap: timeMap
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

    static func sourceInsertions(
        for source: FinalExportSourceInput,
        timeMap: TimelineTimeMap
    ) -> [FinalExportSourceInsertion] {
        timeMap.mediaInsertions(TimelineMediaInsertionRequest(
            activeTakeStart: source.activeTakeStart,
            sourceTimeAtActiveStart: source.sourceTimeAtActiveStart,
            sourceEnd: source.duration
        )).compactMap { insertion in
            guard insertion.duration > .zero else { return nil }
            return FinalExportSourceInsertion(
                kind: source.kind,
                sourceStart: insertion.sourceStart.cmTime,
                compositionStart: insertion.compositionStart.cmTime,
                duration: insertion.duration.cmTime
            )
        }
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

    private struct RenderSegmentRequest {
        let settings: RecordingSettings
        let sceneEvents: [RecordingSceneEvent]
        let timeMap: TimelineTimeMap
        let renderSize: CGSize
        let sources: [FinalExportSourceInput]
        let sourceInsertions: [FinalExportSourceInsertion]
        let transitionSampleInterval: TimeInterval
    }

    private static func renderSegments(_ request: RenderSegmentRequest) -> [FinalExportRenderSegment] {
        let fallbackScene = RecordingScene(settings: request.settings)
        let timeMap = request.timeMap
        var insertionsByKind: [SceneLayerKind: [FinalExportSourceInsertion]] = [:]
        for insertion in request.sourceInsertions {
            insertionsByKind[insertion.kind, default: []].append(insertion)
        }
        let sourceTakeRanges = request.sources.map { source in
            CMTimeRange(start: source.activeTakeStart, end: CMTimeMinimum(source.activeTakeEnd, timeMap.takeDuration.cmTime))
        }
        let takeBoundaries = RecordingSceneTimeline.takeBoundaries(RecordingSceneTimeline.BoundaryRequest(
            sceneEvents: request.sceneEvents,
            duration: timeMap.takeDuration.cmTime,
            sourceTimeRanges: sourceTakeRanges,
            transitionSampleInterval: request.transitionSampleInterval
        ))
        var outputBoundaries = takeBoundaries.map { timeMap.outputTime(forTake: $0) }
        for range in timeMap.keptRanges {
            outputBoundaries.append(range.outputStart.cmTime)
            outputBoundaries.append(range.outputEnd.cmTime)
        }
        outputBoundaries.append(.zero)
        outputBoundaries.append(timeMap.outputDuration.cmTime)
        let uniqueBoundaries = RecordingSceneTimeline.sortedUniqueBoundaries(
            outputBoundaries,
            duration: timeMap.outputDuration.cmTime
        )

        var scenes: [RecordingScene] = []
        var ranges: [CMTimeRange] = []
        if uniqueBoundaries.count >= 2 {
            for index in 0..<(uniqueBoundaries.count - 1) {
                let start = uniqueBoundaries[index]
                let end = uniqueBoundaries[index + 1]
                guard CMTimeCompare(end, start) > 0 else { continue }
                let takeTime = timeMap.takeTime(forOutput: start)
                scenes.append(RecordingSceneTimeline.scene(
                    at: takeTime.seconds,
                    sceneEvents: request.sceneEvents,
                    fallbackScene: fallbackScene
                ))
                ranges.append(CMTimeRange(start: start, duration: CMTimeSubtract(end, start)))
            }
        }
        if ranges.isEmpty {
            scenes = [fallbackScene]
            ranges = [CMTimeRange(start: .zero, duration: timeMap.outputDuration.cmTime)]
        }

        return ranges.indices.map { index in
            let endScene = scenes.indices.contains(index + 1) ? scenes[index + 1] : scenes[index]
            let activeLayerOrder = activeLayerOrder(
                startScene: scenes[index],
                endScene: endScene,
                insertionsByKind: insertionsByKind,
                timeRange: ranges[index],
                renderSize: request.renderSize
            )
            return FinalExportRenderSegment(
                timeRange: ranges[index],
                scene: scenes[index],
                activeLayerOrder: activeLayerOrder
            )
        }
    }

    private static func activeLayerOrder(
        startScene: RecordingScene,
        endScene: RecordingScene,
        insertionsByKind: [SceneLayerKind: [FinalExportSourceInsertion]],
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
            (insertionsByKind[kind] ?? []).contains { sourceIsActive($0, during: timeRange) }
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
        .optimizedWriter
    }

    static func transitionSampleInterval(for settings: RecordingSettings) -> TimeInterval {
        1.0 / Double(max(15, min(240, settings.framesPerSecond)))
    }
}
