import CoreGraphics

enum SceneLayerFit {
    struct Request: Equatable {
        let kind: SceneLayerKind
        let layout: SceneLayout
        let visibleSources: Set<CaptureSource>
        let removesCameraBackgroundAfterRecording: Bool
        let sourceAspectRatio: CGFloat
        let canvasAspectRatio: CGFloat
        let scale: CGFloat
    }

    static func constrainsScreenFillToCameraSlot(
        layout: SceneLayout,
        visibleSources: Set<CaptureSource>,
        removesCameraBackgroundAfterRecording: Bool
    ) -> Bool {
        guard visibleSources.contains(.screen),
              visibleSources.contains(.camera),
              !removesCameraBackgroundAfterRecording else {
            return false
        }

        let cameraFrame = SceneLayerResizing.clamped(layout.cameraFrame.standardized)
        let epsilon: CGFloat = 0.001
        let spansCanvasWidth = cameraFrame.minX <= epsilon
            && cameraFrame.maxX >= 1 - epsilon
            && cameraFrame.height < 0.95
        let spansCanvasHeight = cameraFrame.minY <= epsilon
            && cameraFrame.maxY >= 1 - epsilon
            && cameraFrame.width < 0.95
        return spansCanvasWidth || spansCanvasHeight
    }

    static func frame(_ request: Request) -> CGRect {
        let fitted: CGRect
        if request.kind == .screen,
           constrainsScreenFillToCameraSlot(
            layout: request.layout,
            visibleSources: request.visibleSources,
            removesCameraBackgroundAfterRecording: request.removesCameraBackgroundAfterRecording
           ) {
            fitted = SceneSlotGeometry.screenSlot(
                in: request.layout,
                enabledSources: request.visibleSources
            )
        } else {
            fitted = SceneLayout.canvasFillingFrame(
                sourceAspectRatio: request.sourceAspectRatio,
                canvasAspectRatio: request.canvasAspectRatio
            )
        }
        return SceneLayout.scaledAroundCenter(fitted, scale: request.scale)
    }
}
