import CoreGraphics

enum SceneCanvasOrigin {
    case lowerLeft
    case upperLeft
}

enum SceneLayoutProjection {
    static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func frontToBackOrder(for layout: SceneLayout) -> [SceneLayerKind] {
        layout.graph.frontToBackOrder
    }

    static func backToFrontOrder(fromFrontToBackOrder order: [SceneLayerKind]) -> [SceneLayerKind] {
        Array(order.reversed())
    }

    static func topLayer(in layout: SceneLayout, enabledSources: Set<CaptureSource>) -> SceneLayerKind? {
        layout.graph.frontToBackOrder.first { enabledSources.contains($0.source) }
    }

    static func reorderedBackToFrontOrder(
        moving dropped: SceneLayerKind,
        onto target: SceneLayerKind,
        in layout: SceneLayout
    ) -> [SceneLayerKind]? {
        guard dropped != target else { return nil }

        var displayOrder = frontToBackOrder(for: layout)
        guard let from = displayOrder.firstIndex(of: dropped),
              let originalTargetIndex = displayOrder.firstIndex(of: target) else {
            return nil
        }

        displayOrder.remove(at: from)
        guard let targetIndex = displayOrder.firstIndex(of: target) else {
            return nil
        }

        let insertionIndex = originalTargetIndex > from ? targetIndex + 1 : targetIndex
        displayOrder.insert(dropped, at: insertionIndex)
        return backToFrontOrder(fromFrontToBackOrder: displayOrder)
    }

    static func normalizedFrame(for kind: SceneLayerKind, in layout: SceneLayout) -> CGRect {
        layout.graph.frame(for: kind)
    }

    static func normalizedFrame(
        for kind: SceneLayerKind,
        in settings: RecordingSettings,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> CGRect {
        normalizedFrame(
            for: kind,
            sceneLayout: settings.sceneLayout,
            enabledSources: settings.enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource
        )
    }

    static func normalizedFrame(
        for kind: SceneLayerKind,
        in scene: RecordingScene,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> CGRect {
        normalizedFrame(
            for: kind,
            sceneLayout: scene.sceneLayout,
            enabledSources: scene.enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource
        )
    }

    static func normalizedFrame(
        for kind: SceneLayerKind,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> CGRect {
        sceneLayout.graph.normalizedFrame(
            for: kind,
            enabledSources: enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource
        )
    }

    static func denormalized(
        _ frame: CGRect,
        in canvas: CGRect,
        origin: SceneCanvasOrigin
    ) -> CGRect {
        let y: CGFloat
        switch origin {
        case .lowerLeft:
            y = canvas.minY + frame.minY * canvas.height
        case .upperLeft:
            y = canvas.minY + (1 - frame.maxY) * canvas.height
        }

        return CGRect(
            x: canvas.minX + frame.minX * canvas.width,
            y: y,
            width: frame.width * canvas.width,
            height: frame.height * canvas.height
        )
    }

    static func denormalized(
        _ frame: CGRect,
        in size: CGSize,
        origin: SceneCanvasOrigin
    ) -> CGRect {
        denormalized(frame, in: CGRect(origin: .zero, size: size), origin: origin)
    }

    static func padded(_ rect: CGRect, in canvas: CGRect, padding: CGFloat) -> CGRect {
        let clampedPadding = max(0, min(0.16, padding))
        guard clampedPadding > 0, rect.width > 1, rect.height > 1 else { return rect }

        let inset = min(canvas.width, canvas.height) * clampedPadding
        let dx = min(inset, max(0, (rect.width - 1) / 2))
        let dy = min(inset, max(0, (rect.height - 1) / 2))
        return rect.insetBy(dx: dx, dy: dy)
    }

    static func sourceCornerRadius(for rect: CGRect, canvasPadding: CGFloat) -> CGFloat {
        guard canvasPadding > 0.001, rect.width > 0, rect.height > 0 else { return 0 }
        return min(32, max(8, min(rect.width, rect.height) * 0.04))
    }

    static func projectedFrame(
        for kind: SceneLayerKind,
        in canvas: CGRect,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        canvasPadding: CGFloat,
        origin: SceneCanvasOrigin,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> CGRect {
        let normalizedFrame = normalizedFrame(
            for: kind,
            sceneLayout: sceneLayout,
            enabledSources: enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource
        )
        return padded(
            denormalized(normalizedFrame, in: canvas, origin: origin),
            in: canvas,
            padding: canvasPadding
        )
    }
}

extension SceneLayerKind {
    var source: CaptureSource {
        switch self {
        case .screen:
            return .screen
        case .camera:
            return .camera
        }
    }
}
