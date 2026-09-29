import AVFoundation
import BlitzRecorderCore
import CoreGraphics
import Foundation

extension Merger {
    static func videoCompositionInstructions(
        sources: [CompositedVideoSource],
        renderSize: CGSize,
        renderSegments: [FinalExportRenderSegment]
    ) -> [AVMutableVideoCompositionInstruction] {
        renderSegments.enumerated().map { index, segment in
            let endScene = renderSegments.indices.contains(index + 1)
                ? renderSegments[index + 1].scene
                : segment.scene
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange
            instruction.layerInstructions = layerInstructions(
                sources: sources,
                startScene: segment.scene,
                endScene: endScene,
                activeLayerOrder: segment.activeLayerOrder,
                renderSize: renderSize,
                timeRange: segment.timeRange
            ).reversed()
            instruction.backgroundColor = segment.scene.canvasBackgroundStyle.appearance.solidCGColor
            return instruction
        }
    }

    struct VideoInstructionsRequest {
        let sources: [CompositedVideoSource]
        let renderSegments: [FinalExportRenderSegment]
        let settings: RecordingSettings
        let edits: TimelineEdits
        let timeMap: TimelineTimeMap
        let cursorTrack: CursorPresentationTrack
    }

    static func metalVideoCompositionInstructions(_ request: VideoInstructionsRequest) -> [MetalExportInstruction] {
        let sourceDescriptors = request.sources.map {
            MetalExportSourceDescriptor(
                kind: $0.kind,
                trackID: $0.compositionTrack.trackID,
                preferredTransform: $0.preferredTransform,
                leadingFrame: ExportLeadingFrame(.init(
                    asset: $0.asset,
                    sourceStart: $0.sourceStart,
                    compositionStart: $0.timeRange.start,
                    frameDuration: CMTime(value: 1, timescale: CMTimeScale(request.settings.framesPerSecond))))
            )
        }
        return request.renderSegments.map { segment in
            MetalExportInstruction(MetalExportInstructionRequest(
                timeRange: segment.timeRange,
                scene: segment.scene,
                settings: request.settings,
                activeLayerOrder: segment.activeLayerOrder,
                sourceDescriptors: sourceDescriptors,
                edits: request.edits,
                timeMap: request.timeMap,
                cursorTrack: request.cursorTrack
            ))
        }
    }

    private static func layerInstructions(
        sources: [CompositedVideoSource],
        startScene: RecordingScene,
        endScene: RecordingScene,
        activeLayerOrder: [SceneLayerKind],
        renderSize: CGSize,
        timeRange: CMTimeRange
    ) -> [AVMutableVideoCompositionLayerInstruction] {
        let startGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: startScene,
            origin: .upperLeft
        )
        let endGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: endScene,
            origin: .upperLeft
        )
        return activeLayerOrder.compactMap { kind -> AVMutableVideoCompositionLayerInstruction? in
            guard let source = sources.first(where: { $0.kind == kind && $0.isActive(during: timeRange) }) else {
                return nil
            }
            let startPlacement = startGeometry.videoPlacement(for: kind)
            let endPlacement = endGeometry.videoPlacement(for: kind)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: source.compositionTrack)
            let startCropRectangle = startPlacement.pixelAlignedOrientedCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            let endCropRectangle = endPlacement.pixelAlignedOrientedCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            let startSourceCropRectangle = startPlacement.pixelAlignedSourceCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            let endSourceCropRectangle = endPlacement.pixelAlignedSourceCropRectangle(
                naturalSize: source.naturalSize,
                preferredTransform: source.preferredTransform
            )
            switch (startSourceCropRectangle, endSourceCropRectangle) {
            case let (.some(start), .some(end)):
                layer.setCropRectangleRamp(
                    fromStartCropRectangle: start,
                    toEndCropRectangle: end,
                    timeRange: timeRange
                )
            case let (.some(rect), .none), let (.none, .some(rect)):
                layer.setCropRectangle(rect, at: timeRange.start)
            case (.none, .none):
                break
            }
            layer.setOpacityRamp(
                fromStartOpacity: Float(startScene.sourceOpacity(for: kind.source)),
                toEndOpacity: Float(endScene.sourceOpacity(for: kind.source)),
                timeRange: timeRange
            )
            layer.setTransformRamp(
                fromStart: startPlacement.transform(
                    naturalSize: source.naturalSize,
                    preferredTransform: source.preferredTransform,
                    cropRectangle: startCropRectangle
                ),
                toEnd: endPlacement.transform(
                    naturalSize: source.naturalSize,
                    preferredTransform: source.preferredTransform,
                    cropRectangle: endCropRectangle
                ),
                timeRange: timeRange
            )
            return layer
        }
    }
}
