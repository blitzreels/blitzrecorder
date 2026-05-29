import CoreGraphics

enum PreviewStageEditing {
    static func layer(
        at point: CGPoint,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        frameForLayer: (SceneLayerKind) -> CGRect
    ) -> SceneLayerKind? {
        for layer in SceneLayoutProjection.frontToBackOrder(for: sceneLayout) where enabledSources.contains(layer.source) {
            if frameForLayer(layer).contains(point) {
                return layer
            }
        }
        return nil
    }

    static func resizeAnchor(at point: CGPoint, in frame: CGRect) -> ResizeAnchor? {
        resizeTargets(for: frame).first { $0.1.contains(point) }?.0
    }

    static func resizeHandles(for frame: CGRect) -> [ResizeAnchor: CGRect] {
        let size: CGFloat = 18
        let half = size / 2
        return [
            .topLeft: CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ]
    }

    static func resizeTargets(for frame: CGRect) -> [(ResizeAnchor, CGRect)] {
        resizeHandles(for: frame).map { ($0.key, $0.value) }
            + edgeHitAreas(for: frame).map { ($0.key, $0.value) }
    }

    static func edgeGrips(for frame: CGRect) -> [ResizeAnchor: CGRect] {
        [
            .top: CGRect(x: frame.midX - 14, y: frame.maxY - 2, width: 28, height: 4),
            .bottom: CGRect(x: frame.midX - 14, y: frame.minY - 2, width: 28, height: 4),
            .left: CGRect(x: frame.minX - 2, y: frame.midY - 14, width: 4, height: 28),
            .right: CGRect(x: frame.maxX - 2, y: frame.midY - 14, width: 4, height: 28)
        ]
    }

    static func edgeHitAreas(for frame: CGRect) -> [ResizeAnchor: CGRect] {
        let thickness: CGFloat = 12
        let half = thickness / 2
        return [
            .top: CGRect(x: frame.minX, y: frame.maxY - half, width: frame.width, height: thickness),
            .bottom: CGRect(x: frame.minX, y: frame.minY - half, width: frame.width, height: thickness),
            .left: CGRect(x: frame.minX - half, y: frame.minY, width: thickness, height: frame.height),
            .right: CGRect(x: frame.maxX - half, y: frame.minY, width: thickness, height: frame.height)
        ]
    }

    static func cameraCropDragMode(
        at point: CGPoint,
        cropFrame: CGRect,
        allowsCameraCropInteraction: Bool
    ) -> DragMode.Kind? {
        guard allowsCameraCropInteraction else { return nil }
        if let anchor = resizeAnchor(at: point, in: cropFrame) {
            return .cropResize(anchor)
        }
        if cropFrame.contains(point) {
            return .cropMove
        }
        return nil
    }

    static func screenCropDragMode(at point: CGPoint, cropFrame: CGRect) -> DragMode.Kind? {
        if let anchor = resizeAnchor(at: point, in: cropFrame) {
            return .screenCropResize(anchor)
        }
        if cropFrame.contains(point) {
            return .screenCropMove
        }
        return nil
    }
}

struct DragMode: Equatable {
    enum Kind: Equatable {
        case move
        case resize(ResizeAnchor)
        case cropMove
        case cropResize(ResizeAnchor)
        case screenCropMove
        case screenCropResize(ResizeAnchor)

        var isResize: Bool {
            switch self {
            case .resize:
                return true
            case .move, .cropMove, .cropResize, .screenCropMove, .screenCropResize:
                return false
            }
        }
    }

    let kind: Kind
    let layer: SceneLayerKind
    let startPoint: CGPoint
    let startFrame: CGRect
    let startCropAmount: CGPoint
    let startCropPosition: CGPoint
}
