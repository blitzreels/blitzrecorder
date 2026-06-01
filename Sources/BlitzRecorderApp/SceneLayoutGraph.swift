import CoreGraphics

struct SceneLayoutItem: Equatable {
    let kind: SceneLayerKind
    var frame: CGRect
}

struct ResolvedSceneLayoutItem: Equatable {
    let kind: SceneLayerKind
    var normalizedFrame: CGRect
}

struct SceneLayoutGraph: Equatable {
    var items: [SceneLayoutItem]
    var layerOrder: [SceneLayerKind]

    init(items: [SceneLayoutItem], layerOrder: [SceneLayerKind]) {
        self.items = items
        self.layerOrder = layerOrder
    }

    init(layout: SceneLayout) {
        self.init(
            items: [
                SceneLayoutItem(kind: .screen, frame: layout.screenFrame),
                SceneLayoutItem(kind: .camera, frame: layout.cameraFrame)
            ],
            layerOrder: layout.layerOrder
        )
    }

    func frame(for kind: SceneLayerKind) -> CGRect {
        items.first { $0.kind == kind }?.frame ?? .zero
    }

    var backToFrontOrder: [SceneLayerKind] {
        layerOrder.filter { kind in
            items.contains { $0.kind == kind }
        }
    }

    var frontToBackOrder: [SceneLayerKind] {
        Array(backToFrontOrder.reversed())
    }

    func activeItems(
        enabledSources: Set<CaptureSource>,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> [ResolvedSceneLayoutItem] {
        let visibleItems = backToFrontOrder.compactMap { kind -> SceneLayoutItem? in
            guard enabledSources.contains(kind.source) else { return nil }
            return items.first { $0.kind == kind }
        }
        guard fillsCanvasWhenOnlyVideoSource, visibleItems.count == 1 else {
            return visibleItems.map {
                ResolvedSceneLayoutItem(kind: $0.kind, normalizedFrame: $0.frame)
            }
        }
        return [ResolvedSceneLayoutItem(kind: visibleItems[0].kind, normalizedFrame: SceneLayoutProjection.fullFrame)]
    }

    func normalizedFrame(
        for kind: SceneLayerKind,
        enabledSources: Set<CaptureSource>,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> CGRect {
        activeItems(
            enabledSources: enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource
        )
        .first { $0.kind == kind }?
        .normalizedFrame ?? frame(for: kind)
    }
}

extension SceneLayout {
    var graph: SceneLayoutGraph {
        SceneLayoutGraph(layout: self)
    }

    func resolvedItems(
        enabledSources: Set<CaptureSource>,
        fillsCanvasWhenOnlyVideoSource: Bool
    ) -> [ResolvedSceneLayoutItem] {
        graph.activeItems(
            enabledSources: enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource
        )
    }
}
