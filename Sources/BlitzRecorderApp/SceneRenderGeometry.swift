import CoreGraphics

struct SceneRenderGeometry {
    let canvas: CGRect
    let scene: RecordingScene
    let origin: SceneCanvasOrigin

    var activeLayerOrder: [SceneLayerKind] {
        scene.sceneLayout.layerOrder.filter { scene.enabledSources.contains($0.source) }
    }

    func targetRect(for kind: SceneLayerKind) -> CGRect {
        SceneLayoutProjection.projectedFrame(
            for: kind,
            in: canvas,
            sceneLayout: scene.sceneLayout,
            enabledSources: scene.enabledSources,
            canvasPadding: scene.canvasPadding,
            origin: origin,
            fillsCanvasWhenOnlyVideoSource: true
        )
    }

    func normalizedFrame(for kind: SceneLayerKind) -> CGRect {
        SceneLayoutProjection.normalizedFrame(
            for: kind,
            sceneLayout: scene.sceneLayout,
            enabledSources: scene.enabledSources,
            fillsCanvasWhenOnlyVideoSource: true
        )
    }

    func videoPlacement(for kind: SceneLayerKind) -> VideoRenderPlacement {
        VideoRenderPlacement(
            kind: kind,
            targetRect: targetRect(for: kind),
            sourceCropAmount: kind == .camera ? scene.cameraCropAmount : .zero,
            sourceCropPosition: kind == .camera ? scene.cameraCropPosition : .zero
        )
    }

    func sourceCornerRadius(for kind: SceneLayerKind) -> CGFloat {
        SceneLayoutProjection.sourceCornerRadius(
            for: targetRect(for: kind),
            canvasPadding: scene.canvasPadding
        )
    }

    func sourceMaskPath() -> CGPath? {
        let path = CGMutablePath()
        var hasRoundedSource = false
        for kind in activeLayerOrder {
            let rect = targetRect(for: kind)
            let radius = sourceCornerRadius(for: kind)
            guard radius > 0 else { continue }
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            hasRoundedSource = true
        }
        return hasRoundedSource ? path : nil
    }

    func isFullCanvasFrame(for kind: SceneLayerKind) -> Bool {
        normalizedFrame(for: kind).isAlmostFullCanvasFrame
    }

    func isFullCanvasWidth(for kind: SceneLayerKind) -> Bool {
        let frame = normalizedFrame(for: kind)
        return abs(frame.minX) <= 0.0001 && abs(frame.width - 1) <= 0.0001
    }

    func sourceFrame(
        for kind: SceneLayerKind,
        sourceAspectRatio: CGFloat,
        sourceCropAmount: CGPoint? = nil,
        sourceCropPosition: CGPoint? = nil
    ) -> CGRect {
        videoPlacement(
            for: kind,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
        .sourceFrame(sourceAspectRatio: sourceAspectRatio)
    }

    func sourceCropRectangle(for kind: SceneLayerKind, sourceExtent: CGRect) -> CGRect {
        videoPlacement(for: kind).sourceCropRectangle(sourceExtent: sourceExtent)
    }

    func cameraCropSourceFrame(sourceAspectRatio: CGFloat) -> CGRect {
        sourceFrame(
            for: .camera,
            sourceAspectRatio: sourceAspectRatio,
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )
    }

    func cameraCropFrame(
        sourceAspectRatio: CGFloat,
        sourceCropAmount: CGPoint,
        sourceCropPosition: CGPoint
    ) -> CGRect {
        SourceCropGeometry.cropRectangle(
            source: cameraCropSourceFrame(sourceAspectRatio: sourceAspectRatio),
            target: targetRect(for: .camera),
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
    }

    func baseCameraCropFrame(sourceAspectRatio: CGFloat) -> CGRect {
        cameraCropFrame(
            sourceAspectRatio: sourceAspectRatio,
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )
    }

    private func videoPlacement(
        for kind: SceneLayerKind,
        sourceCropAmount: CGPoint?,
        sourceCropPosition: CGPoint?
    ) -> VideoRenderPlacement {
        VideoRenderPlacement(
            kind: kind,
            targetRect: targetRect(for: kind),
            sourceCropAmount: sourceCropAmount ?? (kind == .camera ? scene.cameraCropAmount : .zero),
            sourceCropPosition: sourceCropPosition ?? (kind == .camera ? scene.cameraCropPosition : .zero)
        )
    }
}

private extension CGRect {
    var isAlmostFullCanvasFrame: Bool {
        abs(minX) <= 0.0001
            && abs(minY) <= 0.0001
            && abs(width - 1) <= 0.0001
            && abs(height - 1) <= 0.0001
    }
}
