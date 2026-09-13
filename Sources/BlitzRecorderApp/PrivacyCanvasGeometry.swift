import CoreGraphics

struct PrivacyCanvasSource {
    let kind: SceneLayerKind
    let frame: CGRect
    let visibleFrame: CGRect

    func pointInSource(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, (point.x - frame.minX) / frame.width)),
                y: min(1, max(0, (point.y - frame.minY) / frame.height)))
    }

    func displayedFrame(_ mask: PrivacyMask) -> CGRect {
        CGRect(x: frame.minX + mask.frame.minX * frame.width,
               y: frame.minY + mask.frame.minY * frame.height,
               width: mask.frame.width * frame.width, height: mask.frame.height * frame.height)
    }
}

enum PrivacyCanvasGeometry {
    struct Request {
        let size: CGSize
        let renderSize: CGSize
        let scene: RecordingScene
        let aspectRatios: [SceneLayerKind: CGFloat]
        let hiddenKinds: Set<SceneLayerKind>
    }

    static func sources(_ request: Request) -> [PrivacyCanvasSource] {
        guard request.renderSize.width > 0, request.renderSize.height > 0,
              request.size.width > 0, request.size.height > 0 else { return [] }
        let scale = min(request.size.width / request.renderSize.width, request.size.height / request.renderSize.height)
        let canvas = CGRect(x: (request.size.width - request.renderSize.width * scale) / 2,
                            y: (request.size.height - request.renderSize.height * scale) / 2,
                            width: request.renderSize.width * scale, height: request.renderSize.height * scale)
        let geometry = SceneRenderGeometry(canvas: CGRect(origin: .zero, size: request.renderSize),
                                           scene: request.scene, origin: .upperLeft)
        func scaled(_ rect: CGRect) -> CGRect {
            CGRect(x: canvas.minX + rect.minX * scale, y: canvas.minY + rect.minY * scale,
                   width: rect.width * scale, height: rect.height * scale)
        }
        return geometry.activeLayerOrder.compactMap { kind in
            guard !request.hiddenKinds.contains(kind), let aspect = request.aspectRatios[kind], aspect > 0 else { return nil }
            let original = geometry.sourceFrame(for: kind, sourceAspectRatio: aspect,
                sourceCropAmount: kind == .camera ? request.scene.cameraCropAmount : request.scene.screenCropAmount,
                sourceCropPosition: kind == .camera ? request.scene.cameraCropPosition : request.scene.screenCropPosition)
            let frame = scaled(original)
            let visible = frame.intersection(scaled(geometry.targetRect(for: kind))).intersection(canvas)
            guard frame.width > 0, frame.height > 0, !visible.isNull, !visible.isEmpty else { return nil }
            return .init(kind: kind, frame: frame, visibleFrame: visible)
        }
    }

    enum Gesture {
        case draw
        case move
        case resize(ResizeAnchor)
    }

    struct Change {
        let frame: CGRect
        let start: CGPoint
        let current: CGPoint
        let gesture: Gesture
    }

    static func changedFrame(_ request: Change) -> CGRect {
        let dx = request.current.x - request.start.x
        let dy = request.current.y - request.start.y
        switch request.gesture {
        case .draw:
            return CGRect(x: min(request.start.x, request.current.x), y: min(request.start.y, request.current.y),
                          width: abs(dx), height: abs(dy))
        case .move:
            return CGRect(x: min(1 - request.frame.width, max(0, request.frame.minX + dx)),
                          y: min(1 - request.frame.height, max(0, request.frame.minY + dy)),
                          width: request.frame.width, height: request.frame.height)
        case .resize(let anchor):
            var left = request.frame.minX
            var top = request.frame.minY
            var right = request.frame.maxX
            var bottom = request.frame.maxY
            if [.topLeft, .bottomLeft, .left].contains(anchor) { left = min(right - 0.005, max(0, left + dx)) }
            if [.topRight, .bottomRight, .right].contains(anchor) { right = max(left + 0.005, min(1, right + dx)) }
            if [.topLeft, .topRight, .top].contains(anchor) { top = min(bottom - 0.005, max(0, top + dy)) }
            if [.bottomLeft, .bottomRight, .bottom].contains(anchor) { bottom = max(top + 0.005, min(1, bottom + dy)) }
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
    }
}
