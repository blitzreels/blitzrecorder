import CoreGraphics
import Foundation

enum PreviewStageSelection {
    enum Mode: Equatable {
        case background
        case inactive
        case pendingScreenCrop
        case pendingCameraCrop
        case screenCrop
        case cameraCrop
        case layer
    }

    struct ModeRequest {
        var isBackgroundLayerSelected: Bool
        var isScreenCropEditingEnabled: Bool
        var hasScreen: Bool
        var canvasIsEmpty: Bool
        var allowsLayerInteraction: Bool
        var allowsCameraCropInteraction: Bool
        var isCameraCropEditingEnabled: Bool
        var selectedLayer: SceneLayerKind
        var hasSelectedSource: Bool
    }

    static func mode(_ request: ModeRequest) -> Mode {
        if request.isBackgroundLayerSelected {
            return .background
        }
        if request.isScreenCropEditingEnabled {
            return request.hasScreen && !request.canvasIsEmpty ? .screenCrop : .pendingScreenCrop
        }
        let isCropMode = request.allowsCameraCropInteraction
            && request.isCameraCropEditingEnabled
            && request.selectedLayer == .camera
        guard request.allowsLayerInteraction || isCropMode else {
            return .inactive
        }
        guard request.hasSelectedSource, !request.canvasIsEmpty else {
            return isCropMode ? .pendingCameraCrop : .inactive
        }
        return isCropMode ? .cameraCrop : .layer
    }

    struct Appearance: Equatable {
        var isCropMode: Bool
        var showsResizeHandles: Bool
        var selectionFrame: CGRect?
        var sourceFrame: CGRect?
        var canvasClip: CGRect?
        var overlayFrame: CGRect?
        var cropToolbarFrame: CGRect?
    }

    struct AppearanceRequest {
        var mode: Mode
        var bounds: CGRect
        var canvasFrame: CGRect
        var screenSourceFrame: CGRect
        var screenCropFrame: CGRect
        var cameraSourceFrame: CGRect
        var cameraCropFrame: CGRect
        var layerFrame: CGRect
        var showsLayerResizeHandles: Bool
    }

    static func appearance(_ request: AppearanceRequest) -> Appearance {
        switch request.mode {
        case .background, .inactive:
            return Appearance(
                isCropMode: false,
                showsResizeHandles: false,
                selectionFrame: nil,
                sourceFrame: nil,
                canvasClip: nil,
                overlayFrame: nil,
                cropToolbarFrame: nil
            )
        case .pendingScreenCrop:
            return Appearance(
                isCropMode: true,
                showsResizeHandles: true,
                selectionFrame: nil,
                sourceFrame: nil,
                canvasClip: nil,
                overlayFrame: nil,
                cropToolbarFrame: nil
            )
        case .pendingCameraCrop:
            return Appearance(
                isCropMode: true,
                showsResizeHandles: false,
                selectionFrame: nil,
                sourceFrame: nil,
                canvasClip: nil,
                overlayFrame: nil,
                cropToolbarFrame: nil
            )
        case .screenCrop:
            return Appearance(
                isCropMode: true,
                showsResizeHandles: true,
                selectionFrame: request.screenCropFrame,
                sourceFrame: request.screenSourceFrame,
                canvasClip: request.canvasFrame,
                overlayFrame: request.bounds,
                cropToolbarFrame: cropToolbarFrame(above: request.screenCropFrame, in: request.bounds)
            )
        case .cameraCrop:
            return Appearance(
                isCropMode: true,
                showsResizeHandles: true,
                selectionFrame: request.cameraCropFrame,
                sourceFrame: request.cameraSourceFrame,
                canvasClip: request.canvasFrame,
                overlayFrame: request.bounds,
                cropToolbarFrame: cropToolbarFrame(above: request.cameraCropFrame, in: request.bounds)
            )
        case .layer:
            return Appearance(
                isCropMode: false,
                showsResizeHandles: request.showsLayerResizeHandles,
                selectionFrame: request.layerFrame,
                sourceFrame: nil,
                canvasClip: request.canvasFrame,
                overlayFrame: request.bounds,
                cropToolbarFrame: nil
            )
        }
    }

    static func cropToolbarFrame(above frame: CGRect, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: 206, height: 40)
        let x = min(bounds.maxX - size.width - 8, max(bounds.minX + 8, frame.midX - size.width / 2))
        let preferredY = frame.maxY + 8
        let fallbackY = frame.maxY - size.height - 8
        let y = preferredY + size.height <= bounds.maxY - 8 ? preferredY : fallbackY
        return CGRect(
            x: x,
            y: max(bounds.minY + 8, y),
            width: size.width,
            height: size.height
        )
    }
}
