import AppKit

extension PreviewStageView {
    var renderedCanvasFrameForTesting: CGRect { canvasFrame }
    var renderedScreenFrameForTesting: CGRect { screenPreview.frame }
    var renderedCameraFrameForTesting: CGRect { cameraPreview.frame }
    var renderedCameraShadowOpacityForTesting: Float { cameraShadowLayer.shadowOpacity }
    var renderedScreenShadowOpacityForTesting: Float { screenShadowLayer.shadowOpacity }
    var renderedScreenCornerRadiusForTesting: CGFloat { screenPreview.layer?.cornerRadius ?? 0 }
    var renderedCameraContentMasksToBoundsForTesting: Bool { cameraPreview.layer?.masksToBounds == true }
    var renderedSelectionFrameForTesting: CGRect? { selectionOverlay.selectionFrame }
    var renderedSelectionShowsResizeHandlesForTesting: Bool { selectionOverlay.showsResizeHandles }
    var renderedCropToolbarFrameForTesting: CGRect? { cropToolbarFrame }
}
