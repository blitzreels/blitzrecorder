import CoreGraphics
import Foundation

enum PreviewStagePassKeys {
    struct LayoutPassKey: Equatable {
        let bounds: CGRect
        let captureLayout: CaptureLayout
        let isCameraCropEditingEnabled: Bool
        let isScreenCropEditingEnabled: Bool
        let enabledSources: Set<CaptureSource>
        let cameraSourceAspectRatio: CGFloat
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

    struct SourceShapeKey: Equatable {
        let bounds: CGRect
        let frame: CGRect
        let isFullscreen: Bool
        let isFullWidth: Bool
        let cameraShadowEnabled: Bool
        let isCameraCropEditingEnabled: Bool
    }

    struct SelectionOverlayKey: Equatable {
        let isBackgroundLayerSelected: Bool
        let isScreenCropEditingEnabled: Bool
        let isCameraCropEditingEnabled: Bool
        let selectedLayer: SceneLayerKind
        let canvasFrame: CGRect
        let bounds: CGRect
        let enabledSources: Set<CaptureSource>
        let allowsLayerInteraction: Bool
        let allowsCameraCropInteraction: Bool
        let sceneLayout: SceneLayout
        let screenCrop: CGRect?
        let cameraCropAmount: CGPoint
        let cameraCropPosition: CGPoint
        let cameraFramePadding: CGFloat
        let cameraContentMode: CameraContentMode
        let screenContentMode: CameraContentMode
        let cameraSourceAspectRatio: CGFloat
        let screenSourceAspectRatio: CGFloat
        let screenFillsSceneFrame: Bool
    }

    struct OutlineOverlayKey: Equatable {
        let bounds: CGRect
        let canvasFrame: CGRect
        let screenFrame: CGRect
        let cameraFrame: CGRect
        let layerOrder: [SceneLayerKind]
        let hasScreenContent: Bool
        let hasCameraContent: Bool
    }

    struct CanvasMaskKey: Equatable {
        let viewFrame: CGRect
        let canvasFrame: CGRect
        let cropEditing: Bool
        let isCamera: Bool
        let isFullscreen: Bool
        let isFullWidth: Bool
    }
}
