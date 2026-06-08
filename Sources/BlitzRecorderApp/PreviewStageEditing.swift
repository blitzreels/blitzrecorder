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

    static func resizeAnchor(at point: CGPoint, in frame: CGRect, constrainedTo constraint: CGRect? = nil) -> ResizeAnchor? {
        resizeTargets(for: frame, constrainedTo: constraint).first { $0.1.contains(point) }?.0
    }

    static func cornerResizeAnchor(at point: CGPoint, in frame: CGRect, constrainedTo constraint: CGRect? = nil) -> ResizeAnchor? {
        cornerResizeTargets(for: frame, constrainedTo: constraint).first { $0.1.contains(point) }?.0
    }

    static func resizeHandles(for frame: CGRect, constrainedTo constraint: CGRect? = nil) -> [ResizeAnchor: CGRect] {
        let size: CGFloat = 18
        let half = size / 2
        return [
            .topLeft: CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ].mapValues { constrained($0, to: constraint) }
    }

    static func resizeTargets(for frame: CGRect, constrainedTo constraint: CGRect? = nil) -> [(ResizeAnchor, CGRect)] {
        resizeHandles(for: frame, constrainedTo: constraint).map { ($0.key, $0.value) }
            + edgeHitAreas(for: frame, constrainedTo: constraint).map { ($0.key, $0.value) }
    }

    static func cornerResizeTargets(for frame: CGRect, constrainedTo constraint: CGRect? = nil) -> [(ResizeAnchor, CGRect)] {
        resizeHandles(for: frame, constrainedTo: constraint).map { ($0.key, $0.value) }
    }

    static func edgeGrips(for frame: CGRect, constrainedTo constraint: CGRect? = nil) -> [ResizeAnchor: CGRect] {
        [
            .top: CGRect(x: frame.midX - 14, y: frame.maxY - 2, width: 28, height: 4),
            .bottom: CGRect(x: frame.midX - 14, y: frame.minY - 2, width: 28, height: 4),
            .left: CGRect(x: frame.minX - 2, y: frame.midY - 14, width: 4, height: 28),
            .right: CGRect(x: frame.maxX - 2, y: frame.midY - 14, width: 4, height: 28)
        ].mapValues { constrained($0, to: constraint) }
    }

    static func edgeHitAreas(for frame: CGRect, constrainedTo constraint: CGRect? = nil) -> [ResizeAnchor: CGRect] {
        let thickness: CGFloat = 12
        let half = thickness / 2
        return [
            .top: CGRect(x: frame.minX, y: frame.maxY - half, width: frame.width, height: thickness),
            .bottom: CGRect(x: frame.minX, y: frame.minY - half, width: frame.width, height: thickness),
            .left: CGRect(x: frame.minX - half, y: frame.minY, width: thickness, height: frame.height),
            .right: CGRect(x: frame.maxX - half, y: frame.minY, width: thickness, height: frame.height)
        ].mapValues { constrained($0, to: constraint) }
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

    static func screenCropDragMode(at point: CGPoint, cropFrame: CGRect, constrainedTo constraint: CGRect? = nil) -> DragMode.Kind? {
        if let anchor = resizeAnchor(at: point, in: cropFrame, constrainedTo: constraint) {
            return .screenCropResize(anchor)
        }
        if cropFrame.contains(point) {
            return .screenCropMove
        }
        return nil
    }

    private static func constrained(_ rect: CGRect, to constraint: CGRect?) -> CGRect {
        guard let constraint, !constraint.isEmpty else { return rect }
        let width = min(rect.width, constraint.width)
        let height = min(rect.height, constraint.height)
        let minX = constraint.minX
        let maxX = constraint.maxX - width
        let minY = constraint.minY
        let maxY = constraint.maxY - height
        return CGRect(
            x: min(maxX, max(minX, rect.minX)),
            y: min(maxY, max(minY, rect.minY)),
            width: width,
            height: height
        )
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
