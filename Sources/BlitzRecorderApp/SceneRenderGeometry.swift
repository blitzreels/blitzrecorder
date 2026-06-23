import CoreGraphics

struct SceneRenderGeometry {
    let canvas: CGRect
    let scene: RecordingScene
    let origin: SceneCanvasOrigin

    var activePlacements: [SceneRenderLayerPlacement] {
        placementPolicy.activePlacements
    }

    var activeItems: [ResolvedSceneLayoutItem] {
        placementPolicy.activeItems
    }

    var activeLayerOrder: [SceneLayerKind] {
        activePlacements.map(\.kind)
    }

    func targetRect(for kind: SceneLayerKind) -> CGRect {
        placementPolicy.targetRect(for: kind)
    }

    func visibleSourceRect(for kind: SceneLayerKind, sourceAspectRatio: CGFloat?) -> CGRect {
        guard kind == .camera,
              scene.cameraContentMode == .fit,
              let sourceAspectRatio,
              sourceAspectRatio > 0 else {
            return targetRect(for: kind)
        }
        return sourceFrame(
            for: .camera,
            sourceAspectRatio: sourceAspectRatio,
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )
    }

    func normalizedFrame(for kind: SceneLayerKind) -> CGRect {
        placementPolicy.normalizedFrame(for: kind)
    }

    func videoPlacement(for kind: SceneLayerKind) -> VideoRenderPlacement {
        placementPolicy.videoPlacement(for: kind)
    }

    func sourceCornerRadius(for kind: SceneLayerKind) -> CGFloat {
        placementPolicy.cornerRadius(for: kind)
    }

    func sourceMaskPath(sourceAspectRatios: [SceneLayerKind: CGFloat] = [:]) -> CGPath? {
        let path = CGMutablePath()
        var hasRoundedSource = false
        for kind in activeLayerOrder {
            let rect = visibleSourceRect(for: kind, sourceAspectRatio: sourceAspectRatios[kind])
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

    func isFullCanvasTarget(for kind: SceneLayerKind) -> Bool {
        targetRect(for: kind).standardized.isAlmostEqual(to: canvas.standardized)
    }

    func isVisibleSourceFullCanvas(for kind: SceneLayerKind, sourceAspectRatio: CGFloat?) -> Bool {
        visibleSourceRect(for: kind, sourceAspectRatio: sourceAspectRatio)
            .standardized
            .isAlmostEqual(to: canvas.standardized)
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
        placementPolicy.videoPlacement(
            for: kind,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
    }

    private var placementPolicy: SceneRenderPlacementPolicy {
        SceneRenderPlacementPolicy(canvas: canvas, scene: scene, origin: origin)
    }
}

private extension CGRect {
    var isAlmostFullCanvasFrame: Bool {
        abs(minX) <= 0.0001
            && abs(minY) <= 0.0001
            && abs(width - 1) <= 0.0001
            && abs(height - 1) <= 0.0001
    }

    func isAlmostEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) <= 0.0001
            && abs(minY - other.minY) <= 0.0001
            && abs(width - other.width) <= 0.0001
            && abs(height - other.height) <= 0.0001
    }
}
