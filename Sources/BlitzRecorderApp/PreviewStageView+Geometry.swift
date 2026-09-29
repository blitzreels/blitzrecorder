import AppKit

extension PreviewStageView {
    func normalizedFrame(for layer: SceneLayerKind) -> CGRect {
        sceneLayout.frame(for: layer)
    }

    func normalizedSelectionFrame(for layer: SceneLayerKind) -> CGRect {
        normalized(selectionFrame(for: layer), in: canvasFrame)
    }

    func projectedFrame(for layer: SceneLayerKind, in canvas: NSRect) -> NSRect {
        let geometry = renderGeometry(in: canvas)
        if layer == .screen,
           screenContentMode == .fit,
           !isScreenCropEditingEnabled {
            return geometry.sourceFrame(
                for: .screen,
                sourceAspectRatio: effectiveScreenSourceAspectRatio
            )
        }
        guard layer == .camera,
              cameraContentMode == .fit,
              !isCameraCropEditingEnabled else {
            return geometry.targetRect(for: layer)
        }
        return geometry.sourceFrame(
            for: .camera,
            sourceAspectRatio: cameraPreview.currentSourceAspectRatio,
            sourceCropAmount: .zero,
            sourceCropPosition: .zero
        )
    }

    func renderGeometry(in canvas: NSRect) -> SceneRenderGeometry {
        let request = PreviewStageLayout.RenderRequest(
            canvas: canvas,
            enabledSources: enabledSources,
            fillsCanvasWhenOnlyVideoSource: fillsCanvasWhenOnlyVideoSource,
            sceneLayout: sceneLayout,
            screenFillsSceneFrame: screenFillsSceneFrame,
            screenCrop: screenCrop,
            screenSourceAspectRatio: effectiveScreenSourceAspectRatio,
            cameraCropAmount: cameraCropAmount,
            cameraCropPosition: cameraCropPosition,
            canvasBackgroundStyle: canvasBackgroundStyle,
            canvasPadding: canvasPadding,
            screenContentMode: screenContentMode,
            cameraContentMode: cameraContentMode,
            cameraFramePadding: cameraFramePadding,
            cameraShadowEnabled: cameraShadowEnabled
        )
        if let cachedRenderGeometry, cachedRenderGeometry.request == request {
            return cachedRenderGeometry.value
        }
        let value = PreviewStageLayout.geometry(request)
        cachedRenderGeometry = (request, value)
        cachedCameraCropGeometry = nil
        cachedScreenCropSourceFrame = nil
        cachedCameraFillFlags = nil
        return value
    }

    var cameraFillFlags: (fullscreen: Bool, fullWidth: Bool, circle: Bool) {
        if let cachedCameraFillFlags { return cachedCameraFillFlags }
        let geometry = renderGeometry(in: canvasFrame)
        let flags = (
            fullscreen: geometry.isFullCanvasFrame(for: .camera),
            fullWidth: geometry.isFullCanvasWidth(for: .camera),
            circle: geometry.rendersCircularCamera
        )
        cachedCameraFillFlags = flags
        return flags
    }

    var isFullscreenCameraPreview: Bool {
        cameraFillFlags.fullscreen
    }

    var effectiveScreenSourceAspectRatio: CGFloat {
        screenSourceAspectRatio
    }

    var isFullWidthCameraPreview: Bool {
        cameraFillFlags.fullWidth
    }

    var isCircularCameraPreview: Bool {
        cameraFillFlags.circle
    }

    func normalized(_ frame: NSRect, in canvas: NSRect) -> CGRect {
        CGRect(
            x: (frame.minX - canvas.minX) / max(1, canvas.width),
            y: (frame.minY - canvas.minY) / max(1, canvas.height),
            width: frame.width / max(1, canvas.width),
            height: frame.height / max(1, canvas.height)
        )
    }
}
