import CoreGraphics

enum PreviewStageLayout {
    struct RenderRequest: Equatable {
        let canvas: CGRect
        let enabledSources: Set<CaptureSource>
        let sceneLayout: SceneLayout
        let screenFillsSceneFrame: Bool
        let screenCrop: CGRect?
        let screenSourceAspectRatio: CGFloat
        let cameraCropAmount: CGPoint
        let cameraCropPosition: CGPoint
        let canvasBackgroundStyle: CanvasBackgroundStyle
        let canvasPadding: CGFloat
        let screenContentMode: CameraContentMode
        let cameraContentMode: CameraContentMode
        let cameraFramePadding: CGFloat
        let cameraShadowEnabled: Bool
    }

    static func fittedCanvas(in rect: CGRect, captureLayout: CaptureLayout) -> CGRect {
        SceneSlotGeometry.canvasFrame(in: rect, captureLayout: captureLayout)
    }

    static func cropEditingCanvas(
        fittedCanvas canvas: CGRect,
        in rect: CGRect,
        cameraSourceAspectRatio: CGFloat,
        geometry: SceneRenderGeometry
    ) -> CGRect {
        let cropGeometry = CameraCropGeometry(
            renderGeometry: geometry,
            sourceAspectRatio: cameraSourceAspectRatio
        )
        let region = canvas.union(cropGeometry.sourceFrame)
        guard region.width > 0, region.height > 0 else { return canvas }

        let scale = min(1, rect.width / region.width, rect.height / region.height)
        let regionX = rect.midX - region.width * scale / 2
        let regionY = rect.midY - region.height * scale / 2
        return CGRect(
            x: regionX + (canvas.minX - region.minX) * scale,
            y: regionY + (canvas.minY - region.minY) * scale,
            width: canvas.width * scale,
            height: canvas.height * scale
        )
    }

    static func geometry(_ request: RenderRequest) -> SceneRenderGeometry {
        SceneRenderGeometry(
            canvas: request.canvas,
            scene: RecordingScene(
                enabledSources: request.enabledSources,
                sceneLayout: request.sceneLayout,
                screenSourceGeometry: ScreenSourceGeometry(
                    fillsSceneFrame: request.screenFillsSceneFrame,
                    normalizedCrop: request.screenCrop,
                    sourceAspectRatio: request.screenSourceAspectRatio
                ),
                cameraCropAmount: request.cameraCropAmount,
                cameraCropPosition: request.cameraCropPosition,
                canvasBackgroundStyle: request.canvasBackgroundStyle,
                canvasPadding: request.canvasPadding,
                screenContentMode: request.screenContentMode,
                cameraContentMode: request.cameraContentMode,
                cameraFramePadding: request.cameraFramePadding,
                cameraShadowEnabled: request.cameraShadowEnabled
            ),
            origin: .lowerLeft
        )
    }

    static func sourceCornerRadius(for rect: CGRect) -> CGFloat {
        guard !rect.isEmpty else { return 0 }
        return min(18, max(8, min(rect.width, rect.height) * 0.08))
    }

    static func cameraPreviewCornerRadius(
        bounds: CGRect,
        isFullscreen: Bool,
        isFullWidth: Bool
    ) -> CGFloat {
        let paddedRadius = SceneLayoutProjection.sourceCornerRadius(for: bounds, normalizedRadius: 0)
        if paddedRadius > 0 { return paddedRadius }
        if isFullscreen || isFullWidth { return 0 }
        return sourceCornerRadius(for: bounds)
    }
}
