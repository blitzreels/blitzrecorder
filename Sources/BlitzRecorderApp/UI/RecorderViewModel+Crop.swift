import CoreGraphics
import Foundation

extension RecorderViewModel {
    struct CameraCropZoomChange {
        let layer: SceneLayerKind
        let zoom: CGFloat
    }

    /// The committed crop of Camera 1 or Camera 2.
    func cameraCrop(for layer: SceneLayerKind) -> LayerCropControl {
        layer == .secondCamera
            ? LayerCropControl(amount: settings.secondCameraCropAmount, position: settings.secondCameraCropPosition)
            : LayerCropControl(amount: settings.cameraCropAmount, position: settings.cameraCropPosition)
    }

    func setCameraCropZoom(_ change: CameraCropZoomChange) {
        setCameraCrop(.init(layer: change.layer, crop: .init(
            amount: CGPoint(x: change.zoom, y: change.zoom),
            position: cameraCrop(for: change.layer).position
        )))
    }

    func setCameraCrop(_ change: CameraCropChange) {
        if isCameraCropMode(change.layer) {
            previewStage.updateCameraCropDraft(amount: change.crop.amount, position: change.crop.position)
        } else {
            coordinator.setCameraCrop(change)
            syncSettings()
        }
    }

    /// Crops Camera 1 or Camera 2 on the canvas; Done and Cancel in the canvas toolbar end it.
    func beginCameraCropMode(_ layer: SceneLayerKind) {
        guard canEditCameraCrop else { return }
        cancelScreenSplitPreview()
        cancelScreenCropMode()
        if canvas.isCameraCropModeEnabled { cancelCameraCropMode() }
        selectLayer(layer)
        previewStage.beginCameraCropEditing(layer)
        canvas.cameraCropModeLayer = layer
        canvas.isCameraCropModeEnabled = true
        syncPreviewInteractionState()
    }

    func applyCameraCropMode() {
        previewStage.commitCameraCropEditing()
        canvas.isCameraCropModeEnabled = false
        syncPreviewInteractionState()
    }

    func cancelCameraCropMode() {
        previewStage.cancelCameraCropEditing()
        canvas.isCameraCropModeEnabled = false
        syncPreviewInteractionState()
    }

    func isCameraCropMode(_ layer: SceneLayerKind) -> Bool {
        canvas.isCameraCropModeEnabled && canvas.cameraCropModeLayer == layer
    }

    func resetCameraCrop(_ layer: SceneLayerKind) {
        setCameraCrop(.init(layer: layer, crop: .init(amount: .zero, position: .zero)))
    }

    func beginScreenCropMode() {
        guard canEditScene, isSourceConfigured(.screen) else { return }
        cancelScreenSplitPreview()
        cancelCameraCropMode()
        selectLayer(.screen)
        screenCaptureAreaSelection = .manualCrop
        coordinator.beginScreenCropEditing()
        syncSettings()
        previewStage.beginScreenCropEditing(crop: settings.screenCrop)
        canvas.isScreenCropModeEnabled = true
        screenCaptureAreaSelection = .manualCrop
        syncPreviewInteractionState()
    }

    func applyScreenCropMode() {
        previewStage.commitScreenCropEditing()
        syncPreviewInteractionState()
    }

    func cancelScreenCropMode() {
        guard canvas.isScreenCropModeEnabled || previewStage.isScreenCropEditingEnabled else { return }
        previewStage.cancelScreenCropEditing()
        coordinator.endScreenCropEditing()
        canvas.isScreenCropModeEnabled = false
        syncSettings()
        syncPreviewInteractionState()
    }

    func resetScreenCropMode() {
        if canvas.isScreenCropModeEnabled {
            previewStage.resetScreenCropDraft()
        } else {
            clearScreenCrop()
        }
    }

    var screenCropLabel: String {
        guard let crop = settings.screenCrop else {
            return settings.usesPickedScreenContent ? "Picked content" : "Full display"
        }
        let width = Int((crop.width * 100).rounded())
        let height = Int((crop.height * 100).rounded())
        if screenCaptureAreaSelection == .activeWindow {
            return "Active window"
        }
        return "Manual crop · \(width)% x \(height)%"
    }
}
