import CoreGraphics
import Foundation

extension RecorderViewModel {
    func setCameraCropAmount(_ amount: CGPoint) {
        coordinator.setCameraCropAmount(amount)
        syncSettings()
    }

    func setCameraCropPosition(_ position: CGPoint) {
        coordinator.setCameraCropPosition(position)
        syncSettings()
    }

    func setCameraCropZoom(_ zoom: CGFloat) {
        setCameraCropPreset(
            amount: CGPoint(x: zoom, y: zoom),
            position: settings.cameraCropPosition
        )
    }

    func setCameraCropPreset(amount: CGPoint, position: CGPoint) {
        if isCameraCropModeEnabled {
            previewStage.updateCameraCropDraft(amount: amount, position: position)
        } else {
            coordinator.setCameraCropAmount(amount)
            coordinator.setCameraCropPosition(position)
            syncSettings()
        }
    }

    func beginCameraCropMode() {
        guard canEditCameraCrop else { return }
        cancelScreenSplitPreview()
        cancelScreenCropMode()
        selectLayer(.camera)
        previewStage.beginCameraCropEditing()
        isCameraCropModeEnabled = true
        syncPreviewInteractionState()
    }

    func applyCameraCropMode() {
        previewStage.commitCameraCropEditing()
        isCameraCropModeEnabled = false
        syncPreviewInteractionState()
    }

    func cancelCameraCropMode() {
        previewStage.cancelCameraCropEditing()
        isCameraCropModeEnabled = false
        syncPreviewInteractionState()
    }

    func resetCameraCrop() {
        if isCameraCropModeEnabled {
            previewStage.updateCameraCropDraft(amount: .zero, position: .zero)
        } else {
            coordinator.setCameraCropAmount(.zero)
            coordinator.setCameraCropPosition(.zero)
            syncSettings()
        }
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
        isScreenCropModeEnabled = true
        screenCaptureAreaSelection = .manualCrop
        syncPreviewInteractionState()
    }

    func applyScreenCropMode() {
        previewStage.commitScreenCropEditing()
        syncPreviewInteractionState()
    }

    func cancelScreenCropMode() {
        guard isScreenCropModeEnabled || previewStage.isScreenCropEditingEnabled else { return }
        previewStage.cancelScreenCropEditing()
        coordinator.endScreenCropEditing()
        isScreenCropModeEnabled = false
        syncSettings()
        syncPreviewInteractionState()
    }

    func resetScreenCropMode() {
        if isScreenCropModeEnabled {
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
