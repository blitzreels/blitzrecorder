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
                sourceInsertions: sourceInsertions
            )
        )
    }

    static func sourceInsertion(
        for source: FinalExportSourceInput,
        compositionDuration: CMTime
    ) -> FinalExportSourceInsertion {
        let offset = source.timelineOffset
        let sourceStart = CMTimeCompare(offset, .zero) < 0 ? CMTimeMultiplyByFloat64(offset, multiplier: -1) : .zero
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
        sourceInsertions: [FinalExportSourceInsertion]
    ) -> [FinalExportRenderSegment] {
        let fallbackScene = RecordingScene(settings: settings)
        let insertionByKind = Dictionary(uniqueKeysWithValues: sourceInsertions.map { ($0.kind, $0) })
        return RecordingSceneTimeline.segments(
            sceneEvents: sceneEvents,
            fallbackScene: fallbackScene,
            duration: duration,
            sourceTimeRanges: sourceInsertions.map(\.timeRange)
        ).map { segment in
            let geometry = SceneRenderGeometry(
                canvas: CGRect(origin: .zero, size: renderSize),
                scene: segment.scene,
                origin: .upperLeft
            )
            let activeLayerOrder = geometry.activeLayerOrder.filter { kind in
                insertionByKind[kind]?.isActive(at: segment.timeRange.start) == true
            }
            return FinalExportRenderSegment(
                timeRange: segment.timeRange,
                scene: segment.scene,
                activeLayerOrder: activeLayerOrder
            )
        }
    }

    private static func engine(
        settings: RecordingSettings,
        sceneEvents: [RecordingSceneEvent]
    ) -> FinalExportEngine {
        RecordingSceneTimeline.requiresCanvasAwareRendering(settings: settings, sceneEvents: sceneEvents)
            ? .assetExportSession
            : .optimizedWriter
    }
}
