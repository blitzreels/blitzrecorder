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
            enabledSources: scene.renderedSources,
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
        targetRect(for: kind, normalizedFrame: normalizedFrame(for: kind))
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
        let targetRect = targetRect(for: kind, normalizedFrame: normalizedFrame)
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

    private func targetRect(for kind: SceneLayerKind, normalizedFrame: CGRect) -> CGRect {
        let paddedRect = SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(normalizedFrame, in: canvas, origin: origin),
            in: canvas,
            padding: scene.canvasPadding
        )
        guard kind == .screen,
              scene.canvasPadding > 0.001,
              scene.screenSourceGeometry.normalizedCrop == nil else {
            return paddedRect
        }
        return aspectFit(
            sourceAspectRatio: scene.screenSourceGeometry.aspectRatio(),
            in: paddedRect
        )
    }

    private func contentMode(for kind: SceneLayerKind) -> VideoRenderContentMode {
        switch kind {
        case .screen:
            return .aspectFill
        case .camera:
            return .aspectFill
        }
    }

    private func aspectFit(sourceAspectRatio: CGFloat, in rect: CGRect) -> CGRect {
        guard sourceAspectRatio > 0,
              rect.width > 0,
              rect.height > 0 else {
            return rect
        }
        let targetAspectRatio = rect.width / rect.height
        if targetAspectRatio > sourceAspectRatio {
            let width = rect.height * sourceAspectRatio
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
        }
        let height = rect.width / sourceAspectRatio
        return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
    }

    private func defaultSourceCropAmount(for kind: SceneLayerKind) -> CGPoint {
        kind == .camera ? scene.cameraCropAmount : .zero
    }

    private func defaultSourceCropPosition(for kind: SceneLayerKind) -> CGPoint {
        kind == .camera ? scene.cameraCropPosition : .zero
    }
}
