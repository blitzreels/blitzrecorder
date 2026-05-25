import CoreGraphics

enum SceneCanvasOrigin {
    case lowerLeft
    case upperLeft
}

enum SceneLayoutProjection {
    static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func frontToBackOrder(for layout: SceneLayout) -> [SceneLayerKind] {
        Array(layout.layerOrder.reversed())
    }

    static func backToFrontOrder(fromFrontToBackOrder order: [SceneLayerKind]) -> [SceneLayerKind] {
        Array(order.reversed())
    }

    static func topLayer(in layout: SceneLayout, enabledSources: Set<CaptureSource>) -> SceneLayerKind? {
        frontToBackOrder(for: layout).first { enabledSources.contains($0.source) }
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
        switch kind {
        case .screen:
            return layout.screenFrame
        case .camera:
            return layout.cameraFrame
        }
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

    private static func normalizedFrame(
        for kind: SceneLayerKind,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> CGRect {
        guard fillsCanvasWhenOnlyVideoSource,
              enabledSources.contains(kind.source),
              enabledSources.isDisjoint(with: otherVideoSources(for: kind)) else {
            return normalizedFrame(for: kind, in: sceneLayout)
        }

        return fullFrame
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

    private static func otherVideoSources(for kind: SceneLayerKind) -> Set<CaptureSource> {
        switch kind {
        case .screen:
            return [.camera]
        case .camera:
            return [.screen]
        }
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
