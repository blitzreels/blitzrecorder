import AppKit
import QuartzCore

extension PreviewStageView {
    func applyCanvasMask(to view: NSView) {
        guard let layer = view.layer else { return }
        let isCamera = view === cameraPreview
        let cropEditing = isCamera ? isCameraCropEditingEnabled : isScreenCropEditingEnabled
        let key = CanvasMaskKey(
            viewFrame: view.frame,
            canvasFrame: canvasFrame,
            cropEditing: cropEditing,
            isCamera: isCamera,
            isFullscreen: isCamera ? isFullscreenCameraPreview : false,
            isFullWidth: isCamera ? isFullWidthCameraPreview : false,
            isCircle: isCamera ? isCircularCameraPreview : false
        )
        if isCamera {
            if lastCameraMaskKey == key { return }
            lastCameraMaskKey = key
        } else if lastScreenMaskKey == key {
            return
        } else {
            lastScreenMaskKey = key
        }

        let canvasInViewCoords = PreviewStageDrawing.canvasRectInView(
            canvasFrame: canvasFrame,
            viewFrame: view.frame
        )
        let visibleRect = canvasInViewCoords.intersection(view.bounds)
        let radius = cropEditing ? 0 : PreviewStageDrawing.maskCornerRadius(.init(
            isCamera: isCamera,
            rect: visibleRect,
            isFullscreen: isFullscreenCameraPreview,
            isFullWidth: isFullWidthCameraPreview,
            isCircle: isCircularCameraPreview
        ))
        let mask = isCamera ? cameraCanvasMask : screenCanvasMask
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = view.bounds
        if cropEditing {
            if layer.mask !== nil {
                layer.mask = nil
            }
            CATransaction.commit()
            return
        }
        mask.path = PreviewStageDrawing.maskPath(for: visibleRect, radius: radius)
        if layer.mask !== mask {
            layer.mask = mask
        }
        CATransaction.commit()
    }

    func applySourceShape(to view: NSView) {
        let isCamera = view === cameraPreview
        let key = SourceShapeKey(
            bounds: view.bounds,
            frame: view.frame,
            isFullscreen: isCamera ? isFullscreenCameraPreview : false,
            isFullWidth: isCamera ? isFullWidthCameraPreview : false,
            isCircle: isCamera ? isCircularCameraPreview : false,
            cameraShadowEnabled: cameraShadowEnabled,
            isCameraCropEditingEnabled: isCameraCropEditingEnabled
        )
        if isCamera {
            if lastCameraShapeKey == key { return }
            lastCameraShapeKey = key
        } else {
            if lastScreenShapeKey == key { return }
            lastScreenShapeKey = key
        }

        let shape = PreviewStageDrawing.sourceShape(.init(
            isCamera: isCamera,
            rect: view.bounds,
            isFullscreen: isCamera ? isFullscreenCameraPreview : false,
            isFullWidth: isCamera ? isFullWidthCameraPreview : false,
            isCircle: isCamera ? isCircularCameraPreview : false
        ))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let layer = view.layer {
            PreviewStageDrawing.apply(shape, to: layer)
            if isCamera {
                layer.shadowOpacity = 0
                layer.shadowPath = nil
                applyCameraShadow(frame: view.frame, cornerRadius: shape.cornerRadius)
            }
        }
        CATransaction.commit()
    }

    func applyCameraShadow(frame: NSRect, cornerRadius: CGFloat) {
        guard cameraShadowEnabled,
              !isCameraCropEditingEnabled,
              !isFullscreenCameraPreview,
              !frame.isEmpty else {
            cameraShadowLayer.shadowOpacity = 0
            cameraShadowLayer.shadowPath = nil
            return
        }
        cameraShadowLayer.frame = frame
        cameraShadowLayer.shadowOpacity = 0.38
        cameraShadowLayer.shadowPath = PreviewStageDrawing.maskPath(
            for: CGRect(origin: .zero, size: frame.size),
            radius: cornerRadius
        )
    }

    func updateOutlineOverlay() {
        let key = OutlineOverlayKey(
            bounds: bounds,
            canvasFrame: canvasFrame,
            screenFrame: screenPreview.frame,
            cameraFrame: cameraPreview.frame,
            layerOrder: sceneLayout.layerOrder,
            hasScreenContent: screenPreview.hasPreviewContent,
            hasCameraContent: cameraPreview.hasPreviewContent
        )
        if lastOutlineOverlayKey == key {
            return
        }
        lastOutlineOverlayKey = key
        let geometry = renderGeometry(in: canvasFrame)
        outlineOverlay.frame = bounds
        outlineOverlay.canvasFrame = canvasFrame
        outlineOverlay.sourceFrames = geometry.activeLayerOrder
            .filter { hasLiveContent(for: $0) }
            .map { frame(for: $0) }
    }

    func hasLiveContent(for layer: SceneLayerKind) -> Bool {
        switch layer {
        case .screen:
            return screenPreview.hasPreviewContent
        case .camera:
            return cameraPreview.hasPreviewContent
        }
    }

    func frame(for layer: SceneLayerKind) -> NSRect {
        switch layer {
        case .screen:
            return screenPreview.frame
        case .camera:
            return cameraPreview.frame
        }
    }

    func applyLayerOrder() {
        let order = sceneLayout.layerOrder
        if lastLayerOrder == order {
            return
        }
        lastLayerOrder = order
        for (index, kind) in order.enumerated() {
            let zPosition = CGFloat(index)
            switch kind {
            case .screen:
                screenPreview.layer?.zPosition = zPosition
            case .camera:
                cameraPreview.layer?.zPosition = zPosition
                cameraShadowLayer.zPosition = zPosition - 0.5
            }
        }
        safeZoneOverlay.layer?.zPosition = CGFloat(order.count + 1)
        selectionOverlay.layer?.zPosition = CGFloat(order.count + 2)
    }

    func updateSafeZoneOverlayVisibility() {
        let showsSocialSafeZone = captureLayout == .vertical && socialSafeZoneOverlay != .none
        safeZoneOverlay.isHidden = !showsRuleOfThirdsOverlay && !showsSocialSafeZone
    }
}
