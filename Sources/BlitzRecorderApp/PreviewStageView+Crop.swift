import AppKit
import QuartzCore

extension PreviewStageView {
    func updateCameraCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let cropGeometry = cameraCropGeometry()
        guard cropGeometry.sourceFrame.width > 0, cropGeometry.sourceFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        applyCameraCropControl(
            for: cropGeometry.movedCropFrame(
                startCrop,
                delta: PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location)
            ),
            using: cropGeometry
        )
    }

    func updateCameraCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let cropGeometry = cameraCropGeometry()
        guard cropGeometry.sourceFrame.width > 0, cropGeometry.sourceFrame.height > 0 else { return }
        let startCrop = cameraCropFrame(
            amount: dragMode.startCropAmount,
            position: dragMode.startCropPosition
        )
        applyCameraCropControl(
            for: cropGeometry.resizedCropFrame(
                startCrop,
                delta: PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location),
                anchor: anchor
            ),
            using: cropGeometry
        )
    }

    func applyCameraCropControl(for crop: CGRect, using cropGeometry: CameraCropGeometry) {
        guard let control = cropGeometry.control(for: crop) else { return }
        updateCameraCropDraft(amount: control.amount, position: control.position)
    }

    func updateScreenCrop(movingFrom dragMode: DragMode, to location: CGPoint) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        let delta = PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location)
        let moved = dragMode.startFrame.offsetBy(dx: delta.x, dy: delta.y)
        updateScreenCropDraft(screenCropFrame: PreviewStageCropGeometry.clampedPixelFrame(moved, in: sourceFrame))
    }

    func updateScreenCrop(resizingFrom dragMode: DragMode, anchor: ResizeAnchor, to location: CGPoint) {
        let sourceFrame = screenCropSourceFrame()
        guard sourceFrame.width > 0, sourceFrame.height > 0 else { return }
        let delta = PreviewStageCropGeometry.dragDelta(from: dragMode.startPoint, to: location)
        updateScreenCropDraft(
            screenCropFrame: PreviewStageCropGeometry.resizedPixelFrame(
                dragMode.startFrame,
                delta: delta,
                anchor: anchor,
                in: sourceFrame
            )
        )
    }

    func beginCameraCropEditing() {
        guard allowsCameraCropInteraction else { return }
        cameraCropDraftAmount = cameraCropAmount
        cameraCropDraftPosition = cameraCropPosition
        selectedLayer = .camera
        isCameraCropEditingEnabled = true
    }

    func beginScreenCropEditing(crop: CGRect?) {
        screenCropDraft = crop ?? defaultScreenCropDraft()
        selectedLayer = .screen
        isCameraCropEditingEnabled = false
        isScreenCropEditingEnabled = true
    }

    func commitCameraCropEditing() {
        guard let crop = PreviewStageCropSession.committedCameraCrop(
            isEditing: isCameraCropEditingEnabled,
            amount: activeCameraCropAmount,
            position: activeCameraCropPosition
        ) else { return }
        isCameraCropEditingEnabled = false
        cameraCropDraftAmount = nil
        cameraCropDraftPosition = nil
        cameraCropAmount = crop.0
        cameraCropPosition = crop.1
        onCameraCropChanged?(crop.0, crop.1)
    }

    func cancelCameraCropEditing() {
        cameraCropDraftAmount = nil
        cameraCropDraftPosition = nil
        isCameraCropEditingEnabled = false
    }

    func commitScreenCropEditing() {
        guard let draft = PreviewStageCropSession.committedScreenCrop(
            isEditing: isScreenCropEditingEnabled,
            draft: screenCropDraft
        ) else { return }
        isScreenCropEditingEnabled = false
        screenCropDraft = nil
        screenCrop = draft
        onScreenCropChanged?(draft)
    }

    func cancelScreenCropEditing() {
        screenCropDraft = screenCrop
        isScreenCropEditingEnabled = false
    }

    func resetScreenCropDraft() {
        guard isScreenCropEditingEnabled else { return }
        screenCropDraft = defaultScreenCropDraft()
        updateSelectionOverlay()
        invalidateResizeCursorRects()
    }

    func updateCameraCropDraft(amount: CGPoint? = nil, position: CGPoint? = nil) {
        guard isCameraCropEditingEnabled else { return }
        cameraCropDraftAmount = amount ?? activeCameraCropAmount
        cameraCropDraftPosition = position ?? activeCameraCropPosition
        updateSelectionOverlay()
        invalidateResizeCursorRects()
    }

    var activeCameraCropAmount: CGPoint {
        cameraCropDraftAmount ?? cameraCropAmount
    }

    var activeCameraCropPosition: CGPoint {
        cameraCropDraftPosition ?? cameraCropPosition
    }

    func syncPreviewCrop() {
        let amount = isCameraCropEditingEnabled ? .zero : cameraCropAmount
        let position = isCameraCropEditingEnabled ? .zero : cameraCropPosition
        guard cameraPreview.sourceCropAmount != amount || cameraPreview.sourceCropPosition != position else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cameraPreview.sourceCropAmount = amount
        cameraPreview.sourceCropPosition = position
        CATransaction.commit()
    }

    func cameraCropFrame() -> CGRect {
        cameraCropFrame(amount: activeCameraCropAmount, position: activeCameraCropPosition)
    }

    func cameraCropFrame(amount: CGPoint, position: CGPoint) -> CGRect {
        cameraCropGeometry().cropFrame(amount: amount, position: position)
    }

    func cameraCropSourceFrame() -> CGRect {
        cameraCropGeometry().sourceFrame
    }

    func cameraCropGeometry() -> CameraCropGeometry {
        let render = renderGeometry(in: canvasFrame)
        let aspect = cameraPreview.currentSourceAspectRatio
        if let cachedRenderGeometry,
           let cachedCameraCropGeometry,
           cachedCameraCropGeometry.request == cachedRenderGeometry.request,
           cachedCameraCropGeometry.aspect == aspect {
            return cachedCameraCropGeometry.value
        }
        let value = CameraCropGeometry(
            renderGeometry: render,
            sourceAspectRatio: aspect
        )
        if let cachedRenderGeometry {
            cachedCameraCropGeometry = (cachedRenderGeometry.request, aspect, value)
        }
        return value
    }

    func screenCropSourceFrame() -> CGRect {
        let aspect = screenSourceAspectRatio
        if let cachedRenderGeometry,
           let cachedScreenCropSourceFrame,
           cachedScreenCropSourceFrame.request == cachedRenderGeometry.request,
           cachedScreenCropSourceFrame.aspect == aspect {
            return cachedScreenCropSourceFrame.value
        }
        let value = PreviewStageCropGeometry.fittedSourceFrame(
            target: projectedFrame(for: .screen, in: canvasFrame),
            sourceAspectRatio: aspect
        )
        if let cachedRenderGeometry {
            cachedScreenCropSourceFrame = (cachedRenderGeometry.request, aspect, value)
        }
        return value
    }

    func screenCropFrame() -> CGRect {
        PreviewStageCropGeometry.cropFrame(
            in: screenCropSourceFrame(),
            normalizedCrop: screenCropDraft ?? screenCrop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        )
    }

    func defaultScreenCropDraft() -> CGRect {
        PreviewStageCropGeometry.defaultDraft(
            sourceFrame: screenCropSourceFrame(),
            targetFrame: projectedFrame(for: .screen, in: canvasFrame)
        )
    }

    func updateScreenCropDraft(screenCropFrame: CGRect) {
        screenCropDraft = PreviewStageCropGeometry.normalizedCrop(
            pixelFrame: screenCropFrame,
            in: screenCropSourceFrame()
        )
        updateSelectionOverlay()
        invalidateResizeCursorRects()
    }
}
