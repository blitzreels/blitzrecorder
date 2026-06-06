import CoreGraphics

enum SceneSlotGeometry {
    private static let minimumSlotSize: CGFloat = 0.08
    static let shortsTopHalfSlot = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)

    static func screenSlot(in layout: SceneLayout, enabledSources: Set<CaptureSource>) -> CGRect {
        guard enabledSources.contains(.camera) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let cameraFrame = SceneLayerResizing.clamped(layout.cameraFrame.standardized)
        let candidates = [
            CGRect(x: 0, y: cameraFrame.maxY, width: 1, height: 1 - cameraFrame.maxY),
            CGRect(x: 0, y: 0, width: 1, height: cameraFrame.minY),
            CGRect(x: cameraFrame.maxX, y: 0, width: 1 - cameraFrame.maxX, height: 1),
            CGRect(x: 0, y: 0, width: cameraFrame.minX, height: 1)
        ]

        return candidates
            .filter { $0.width >= minimumSlotSize && $0.height >= minimumSlotSize }
            .max { lhs, rhs in
                lhs.width * lhs.height < rhs.width * rhs.height
            }
            ?? SceneLayerResizing.clamped(layout.screenFrame)
    }

    static func targetWindowSlot(in layout: SceneLayout, enabledSources: Set<CaptureSource>) -> CGRect {
        guard enabledSources.contains(.camera) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let canvas = CGRect(x: 0, y: 0, width: 1, height: 1)
        let visibleScreenFrame = layout.screenFrame.standardized.intersection(canvas)
        guard !visibleScreenFrame.isNull, !visibleScreenFrame.isEmpty else {
            return SceneLayerResizing.clamped(layout.screenFrame.standardized)
        }
        return visibleScreenFrame
    }

    static func canvasFrame(in rect: CGRect, captureLayout: CaptureLayout) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return .zero }

        let aspect = captureLayout.aspectRatio
        let rectAspect = rect.width / rect.height
        if rectAspect > aspect {
            let width = floor(rect.height * aspect)
            return CGRect(
                x: rect.midX - width / 2,
                y: rect.minY,
                width: width,
                height: rect.height
            )
        }

        let height = floor(rect.width / aspect)
        return CGRect(
            x: rect.minX,
            y: rect.midY - height / 2,
            width: rect.width,
            height: height
        )
    }

    static func physicalFrame(
        for slot: CGRect,
        in visibleFrame: CGRect,
        captureLayout: CaptureLayout,
        scale: CGFloat = 1
    ) -> CGRect {
        let canvas = canvasFrame(in: visibleFrame, captureLayout: captureLayout)
        let frame = SceneLayoutProjection.denormalized(slot, in: canvas, origin: .lowerLeft)
        return scaled(frame, scale: scale)
    }

    private static func scaled(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let scale = min(1.25, max(0.75, scale))
        let width = frame.width * scale
        let height = frame.height * scale
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
