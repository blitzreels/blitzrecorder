import CoreGraphics

enum PreviewStageLayout {
    struct RenderRequest: Equatable {
        let canvas: CGRect
        let enabledSources: Set<CaptureSource>
        let fillsCanvasWhenOnlyVideoSource: Bool
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

    struct CropEditingCanvasRequest {
        let fittedCanvas: CGRect
        let rect: CGRect
        /// The camera being cropped, whose whole picture must fit on screen.
        let cameraLayer: SceneLayerKind
        let cameraSourceAspectRatio: CGFloat
        let geometry: SceneRenderGeometry
    }

    static func cropEditingCanvas(_ request: CropEditingCanvasRequest) -> CGRect {
        let canvas = request.fittedCanvas
        let rect = request.rect
        let cropGeometry = LayerCropGeometry(
            kind: request.cameraLayer,
            renderGeometry: request.geometry,
            sourceAspectRatio: request.cameraSourceAspectRatio
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
                cameraShadowEnabled: request.cameraShadowEnabled,
                fillsCanvasWhenOnlyVideoSource: request.fillsCanvasWhenOnlyVideoSource
            ),
            origin: .lowerLeft
        )
    }

    static func cameraPreviewCornerRadius(_ request: PreviewStageDrawing.SourceShapeRequest) -> CGFloat {
        if request.isCircle {
            return SceneLayoutProjection.circularCornerRadius(for: request.rect)
        }
        guard request.isFloating else {
            return SceneLayoutProjection.sourceCornerRadius(for: request.rect, normalizedRadius: request.screenCornerRadius)
        }
        if request.isFullscreen || request.isFullWidth { return 0 }
        return SceneLayoutProjection.cameraCornerRadius(for: request.rect, normalizedRadius: request.cameraCornerRadius)
    }
}
