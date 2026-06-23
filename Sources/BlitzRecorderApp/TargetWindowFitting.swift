import CoreGraphics

struct TargetWindowFittingPlan: Equatable {
    let screenSlot: CGRect
    let canvasFrame: CGRect
    let windowFrame: CGRect
    let screenCrop: CGRect
}

enum TargetWindowFitting {
    static func plan(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        captureLayout: CaptureLayout,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        zoom: CGFloat = 1
    ) -> TargetWindowFittingPlan {
        plan(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            captureLayout: captureLayout,
            screenSlot: SceneSlotGeometry.targetWindowSlot(
                in: sceneLayout,
                enabledSources: enabledSources
            ),
            zoom: zoom
        )
    }

    static func plan(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        captureLayout: CaptureLayout,
        screenSlot: CGRect,
        zoom: CGFloat = 1
    ) -> TargetWindowFittingPlan {
        let canvasFrame = SceneSlotGeometry.canvasFrame(
            in: visibleFrame,
            captureLayout: captureLayout
        )
        let unscaledFrame = SceneLayoutProjection.denormalized(
            screenSlot,
            in: canvasFrame,
            origin: .lowerLeft
        )
        let windowFrame = clamped(
            frame: WindowZoomGeometry.sourceFrame(for: unscaledFrame, zoom: zoom),
            in: visibleFrame
        )
        return TargetWindowFittingPlan(
            screenSlot: screenSlot,
            canvasFrame: canvasFrame,
            windowFrame: windowFrame,
            screenCrop: screenCrop(for: windowFrame, in: screenFrame)
        )
    }

    static func screenCrop(for frame: CGRect, in screenFrame: CGRect) -> CGRect {
        let local = frame.intersection(screenFrame)
        guard !local.isEmpty, screenFrame.width > 0, screenFrame.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        return CGRect(
            x: (local.minX - screenFrame.minX) / screenFrame.width,
            y: (screenFrame.maxY - local.maxY) / screenFrame.height,
            width: local.width / screenFrame.width,
            height: local.height / screenFrame.height
        )
    }

    static func clamped(frame: CGRect, in bounds: CGRect) -> CGRect {
        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        let x = min(bounds.maxX - width, max(bounds.minX, frame.minX))
        let y = min(bounds.maxY - height, max(bounds.minY, frame.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }

}
