import CoreGraphics

struct SceneRenderLayerPlacement {
    let kind: SceneLayerKind
    let normalizedFrame: CGRect
    let targetRect: CGRect
    let cornerRadius: CGFloat
    let videoPlacement: VideoRenderPlacement
}

struct SceneRenderPlacementPolicy {
    let canvas: CGRect
    let scene: RecordingScene
    let origin: SceneCanvasOrigin

    var activeItems: [ResolvedSceneLayoutItem] {
        scene.sceneLayout.resolvedItems(
            enabledSources: scene.enabledSources,
            fillsCanvasWhenOnlyVideoSource: true
        )
    }

    var activePlacements: [SceneRenderLayerPlacement] {
        activeItems.map { item in
            layerPlacement(for: item.kind, normalizedFrame: item.normalizedFrame)
        }
    }

    func normalizedFrame(for kind: SceneLayerKind) -> CGRect {
        activeItems.first { $0.kind == kind }?.normalizedFrame
            ?? scene.sceneLayout.graph.frame(for: kind)
    }

    func targetRect(for kind: SceneLayerKind) -> CGRect {
        targetRect(for: normalizedFrame(for: kind))
    }

    func cornerRadius(for kind: SceneLayerKind) -> CGFloat {
        SceneLayoutProjection.sourceCornerRadius(
            for: targetRect(for: kind),
            canvasPadding: scene.canvasPadding
        )
    }

    func videoPlacement(
        for kind: SceneLayerKind,
        sourceCropAmount: CGPoint? = nil,
        sourceCropPosition: CGPoint? = nil
    ) -> VideoRenderPlacement {
        VideoRenderPlacement(
            kind: kind,
            targetRect: targetRect(for: kind),
            sourceCropAmount: sourceCropAmount ?? defaultSourceCropAmount(for: kind),
            sourceCropPosition: sourceCropPosition ?? defaultSourceCropPosition(for: kind),
            contentMode: contentMode(for: kind)
        )
    }

    private func layerPlacement(
        for kind: SceneLayerKind,
        normalizedFrame: CGRect
    ) -> SceneRenderLayerPlacement {
        let targetRect = targetRect(for: normalizedFrame)
        let videoPlacement = VideoRenderPlacement(
            kind: kind,
            targetRect: targetRect,
            sourceCropAmount: defaultSourceCropAmount(for: kind),
            sourceCropPosition: defaultSourceCropPosition(for: kind),
            contentMode: contentMode(for: kind)
        )
        return SceneRenderLayerPlacement(
            kind: kind,
            normalizedFrame: normalizedFrame,
            targetRect: targetRect,
            cornerRadius: SceneLayoutProjection.sourceCornerRadius(
                for: targetRect,
                canvasPadding: scene.canvasPadding
            ),
            videoPlacement: videoPlacement
        )
    }

    private func targetRect(for normalizedFrame: CGRect) -> CGRect {
        SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(normalizedFrame, in: canvas, origin: origin),
            in: canvas,
            padding: scene.canvasPadding
        )
    }

    private func contentMode(for kind: SceneLayerKind) -> VideoRenderContentMode {
        switch kind {
        case .screen, .camera:
            return .aspectFill
        }
    }

    private func defaultSourceCropAmount(for kind: SceneLayerKind) -> CGPoint {
        kind == .camera ? scene.cameraCropAmount : .zero
    }

    private func defaultSourceCropPosition(for kind: SceneLayerKind) -> CGPoint {
        kind == .camera ? scene.cameraCropPosition : .zero
    }
}
