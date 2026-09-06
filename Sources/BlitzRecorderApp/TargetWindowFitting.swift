import CoreGraphics

struct TargetWindowFittingPlan: Equatable {
    let screenSlot: CGRect
    let canvasFrame: CGRect
    let unscaledWindowFrame: CGRect
    let windowFrame: CGRect
    let screenCrop: CGRect
}

enum TargetWindowFitting {
    static func sourceAspectRatio(for settings: RecordingSettings) -> CGFloat {
        let canvas = CGRect(
            x: 0,
            y: 0,
            width: settings.layout.aspectRatio,
            height: 1
        )
        let slot = SceneSlotGeometry.targetWindowSlot(
            in: settings.sceneLayout,
            enabledSources: settings.visibleSources
        )
        let frame = SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(
                slot,
                in: canvas,
                origin: .lowerLeft
            ),
            in: canvas,
            padding: settings.canvasPadding
        )
        guard frame.width > 0, frame.height > 0 else {
            return settings.layout.aspectRatio
        }
        return frame.width / frame.height
    }

    static func plan(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        captureLayout: CaptureLayout,
        sceneLayout: SceneLayout,
        enabledSources: Set<CaptureSource>,
        canvasPadding: CGFloat = 0,
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
            canvasPadding: canvasPadding,
            zoom: zoom
        )
    }

    static func plan(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        captureLayout: CaptureLayout,
        screenSlot: CGRect,
        canvasPadding: CGFloat = 0,
        zoom: CGFloat = 1
    ) -> TargetWindowFittingPlan {
        let canvasFrame = SceneSlotGeometry.canvasFrame(
            in: visibleFrame,
            captureLayout: captureLayout
        )
        let unscaledFrame = SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(
                screenSlot,
                in: canvasFrame,
                origin: .lowerLeft
            ),
            in: canvasFrame,
            padding: canvasPadding
        )
        let windowFrame = fittedFrame(.init(
            requested: WindowZoomGeometry.sourceFrame(for: unscaledFrame, zoom: zoom),
            minimumSize: .zero,
            available: visibleFrame
        ))
        return TargetWindowFittingPlan(
            screenSlot: screenSlot,
            canvasFrame: canvasFrame,
            unscaledWindowFrame: unscaledFrame,
            windowFrame: windowFrame,
            screenCrop: screenCrop(for: windowFrame, in: screenFrame)
        )
    }

    struct FrameRequest {
        let requested: CGRect
        let minimumSize: CGSize
        let available: CGRect
    }

    static func fittedFrame(_ request: FrameRequest) -> CGRect {
        let desired = request.requested
        let available = request.available
        guard desired.width > 0, desired.height > 0,
              available.width > 0, available.height > 0 else { return available }
        let minimumScale = max(
            1,
            request.minimumSize.width / desired.width,
            request.minimumSize.height / desired.height
        )
        let maximumScale = min(available.width / desired.width, available.height / desired.height)
        let scale = min(minimumScale, maximumScale)
        let width = max(request.minimumSize.width, desired.width * scale)
        let height = max(request.minimumSize.height, desired.height * scale)
        return clamped(
            frame: CGRect(x: desired.midX - width / 2, y: desired.midY - height / 2, width: width, height: height),
            in: available
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
