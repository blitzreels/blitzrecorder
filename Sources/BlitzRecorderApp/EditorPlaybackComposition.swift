import AVFoundation
import CoreGraphics
import Foundation

struct EditorPlaybackSceneTimeline {
    let settings: RecordingSettings
    let sceneEvents: [RecordingSceneEvent]
}

struct EditorPlaybackComposition {
    struct AudioInput {
        let source: CaptureSource
        let track: AVCompositionTrack
        let volume: Float
    }

    let composition: AVComposition
    let duration: CMTime
    let renderSize: CGSize
    let frameDuration: CMTime
    let renderSegments: [FinalExportRenderSegment]
    let settings: RecordingSettings
    let sceneEvents: [RecordingSceneEvent]
    let sourceInputs: [FinalExportSourceInput]
    let timeMap: TimelineTimeMap
    let cuts: [TimelineCut]
    let videoKinds: [SceneLayerKind]
    let sourceAspectRatios: [SceneLayerKind: CGFloat]
    let audioInputs: [AudioInput]
    let videoAssets: [SceneLayerKind: AVComposition]
    let makeInstructions: (Set<SceneLayerKind>, [FinalExportRenderSegment]) -> [AVMutableVideoCompositionInstruction]

    func playerItem(
        hiding hiddenKinds: Set<SceneLayerKind> = [],
        muting mutedSources: Set<CaptureSource> = []
    ) -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        if !videoKinds.isEmpty {
            item.videoComposition = videoComposition(hiding: hiddenKinds)
        }
        item.audioMix = audioMix(muting: mutedSources)
        return item
    }

    func videoAsset(for kind: SceneLayerKind) -> AVAsset? {
        videoAssets[kind]
    }

    func updatingSceneTimeline(_ update: EditorPlaybackSceneTimeline) throws -> EditorPlaybackComposition {
        let plan = try FinalExportPlanning.plan(
            settings: update.settings,
            sceneEvents: update.sceneEvents,
            sources: sourceInputs,
            cuts: cuts
        )
        guard plan.renderSize == renderSize else {
            throw RecorderError.exportUnavailable
        }
        return EditorPlaybackComposition(
            composition: composition,
            duration: duration,
            renderSize: renderSize,
            frameDuration: frameDuration,
            renderSegments: plan.renderSegments,
            settings: update.settings,
            sceneEvents: update.sceneEvents,
            sourceInputs: sourceInputs,
            timeMap: timeMap,
            cuts: cuts,
            videoKinds: videoKinds,
            sourceAspectRatios: sourceAspectRatios,
            audioInputs: audioInputs,
            videoAssets: videoAssets,
            makeInstructions: makeInstructions
        )
    }

    func videoComposition(hiding hiddenKinds: Set<SceneLayerKind>) -> AVVideoComposition {
        videoComposition(hiding: hiddenKinds, renderSegments: renderSegments(hiding: hiddenKinds))
    }

    func duration(hiding hiddenKinds: Set<SceneLayerKind>) -> CMTime {
        previewPlan(hiding: hiddenKinds)?.duration ?? duration
    }

    func videoComposition(
        hiding hiddenKinds: Set<SceneLayerKind>,
        overriding scene: RecordingScene,
        at time: CMTime
    ) -> AVVideoComposition {
        let scene = Self.scene(scene, hiding: hiddenKinds)
        return videoComposition(
            hiding: hiddenKinds,
            renderSegments: renderSegments(hiding: hiddenKinds, overriding: scene, at: time)
        )
    }

    func renderSegments(overriding scene: RecordingScene, at time: CMTime) -> [FinalExportRenderSegment] {
        Self.renderSegments(renderSegments, overriding: scene, at: time)
    }

    func renderSegments(
        hiding hiddenKinds: Set<SceneLayerKind>,
        overriding scene: RecordingScene,
        at time: CMTime
    ) -> [FinalExportRenderSegment] {
        Self.renderSegments(renderSegments(hiding: hiddenKinds), overriding: scene, at: time)
    }

    func renderSegments(hiding hiddenKinds: Set<SceneLayerKind>) -> [FinalExportRenderSegment] {
        guard !hiddenKinds.isEmpty else { return renderSegments }
        return previewPlan(hiding: hiddenKinds)?.renderSegments ?? renderSegments.map { segment in
            FinalExportRenderSegment(
                timeRange: segment.timeRange,
                scene: Self.scene(segment.scene, hiding: hiddenKinds),
                activeLayerOrder: segment.activeLayerOrder.filter { !hiddenKinds.contains($0) }
            )
        }
    }

    func normalizedLayerFrames(
        scene: RecordingScene,
        activeLayerOrder: [SceneLayerKind]? = nil,
        hiding hiddenKinds: Set<SceneLayerKind>
    ) -> [(kind: SceneLayerKind, frame: CGRect)] {
        Self.normalizedLayerFrames(
            scene: scene,
            renderSize: renderSize,
            activeLayerOrder: activeLayerOrder,
            hiding: hiddenKinds,
            sourceAspectRatios: sourceAspectRatios
        )
    }

    static func renderSegments(
        _ renderSegments: [FinalExportRenderSegment],
        overriding scene: RecordingScene,
        at time: CMTime
    ) -> [FinalExportRenderSegment] {
        let index = EditorTimelineIndex.containingSegmentIndex(at: time, in: renderSegments)
            ?? renderSegments.firstIndex {
                CMTimeCompare($0.timeRange.start, time) == 0
            }
            ?? renderSegments.firstIndex {
                CMTimeCompare(CMTimeRangeGetEnd($0.timeRange), time) == 0
            }
        guard let index else {
            return renderSegments
        }
        var segments = renderSegments
        let segment = segments[index]
        segments[index] = FinalExportRenderSegment(
            timeRange: segment.timeRange,
            scene: scene,
            activeLayerOrder: segment.activeLayerOrder
        )
        return segments
    }

    static func normalizedLayerFrames(
        scene: RecordingScene,
        renderSize: CGSize,
        activeLayerOrder: [SceneLayerKind]? = nil,
        hiding hiddenKinds: Set<SceneLayerKind>,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> [(kind: SceneLayerKind, frame: CGRect)] {
        guard renderSize.width > 0, renderSize.height > 0 else { return [] }
        let scene = Self.scene(scene, hiding: hiddenKinds)
        let canvas = CGRect(origin: .zero, size: renderSize)
        let geometry = SceneRenderGeometry(canvas: canvas, scene: scene, origin: .upperLeft)
        let layerOrder = activeLayerOrder?.filter { !hiddenKinds.contains($0) } ?? geometry.activeLayerOrder
        return layerOrder
            .compactMap { kind in
                let rect = visibleRect(
                    for: kind,
                    scene: scene,
                    geometry: geometry,
                    sourceAspectRatios: sourceAspectRatios
                )
                guard rect.width > 0, rect.height > 0 else { return nil }
                return (kind, CGRect(
                    x: rect.minX / renderSize.width,
                    y: rect.minY / renderSize.height,
                    width: rect.width / renderSize.width,
                    height: rect.height / renderSize.height
                ))
            }
    }

    private static func scene(_ scene: RecordingScene, hiding hiddenKinds: Set<SceneLayerKind>) -> RecordingScene {
        guard !hiddenKinds.isEmpty else { return scene }
        var scene = scene
        scene.enabledSources.subtract(Set(hiddenKinds.map(\.source)))
        scene.fillsCanvasWhenOnlyVideoSource = true
        return scene
    }

    private func previewPlan(hiding hiddenKinds: Set<SceneLayerKind>) -> FinalExportPlan? {
        guard !hiddenKinds.isEmpty else {
            return FinalExportPlan(
                duration: duration,
                renderSize: renderSize,
                engine: .assetExportSession,
                sourceInsertions: [],
                renderSegments: renderSegments
            )
        }
        var settings = settings
        let hiddenSources = Set(hiddenKinds.map(\.source))
        settings.enabledSources.subtract(hiddenSources)
        let sceneEvents = sceneEvents.map { event in
            var scene = event.scene
            scene.enabledSources.subtract(hiddenSources)
            scene.fillsCanvasWhenOnlyVideoSource = true
            return RecordingSceneEvent(time: event.time, scene: scene, transition: event.transition)
        }
        return try? FinalExportPlanning.plan(
            settings: settings,
            sceneEvents: sceneEvents,
            sources: sourceInputs,
            cuts: cuts
        )
    }

    private static func visibleRect(
        for kind: SceneLayerKind,
        scene: RecordingScene,
        geometry: SceneRenderGeometry,
        sourceAspectRatios: [SceneLayerKind: CGFloat]
    ) -> CGRect {
        guard kind == .camera,
              scene.cameraContentMode == .fit,
              let sourceAspectRatio = sourceAspectRatios[.camera] else {
            return geometry.targetRect(for: kind)
        }
        return geometry.visibleSourceRect(for: .camera, sourceAspectRatio: sourceAspectRatio)
    }

    private func videoComposition(
        hiding hiddenKinds: Set<SceneLayerKind>,
        renderSegments: [FinalExportRenderSegment]
    ) -> AVVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = makeInstructions(hiddenKinds, renderSegments)
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        return videoComposition
    }

    func audioMix(muting mutedSources: Set<CaptureSource>) -> AVAudioMix? {
        guard !audioInputs.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioInputs.map { input in
            let parameters = AVMutableAudioMixInputParameters(track: input.track)
            parameters.setVolume(mutedSources.contains(input.source) ? 0 : input.volume, at: .zero)
            return parameters
        }
        return mix
    }
}
