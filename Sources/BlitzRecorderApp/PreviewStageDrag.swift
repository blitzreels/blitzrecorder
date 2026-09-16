import AppKit
import CoreGraphics

enum PreviewStageDrag {
    static func canvasDelta(from start: CGPoint, to location: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: (location.x - start.x) / max(1, canvasSize.width),
            y: (location.y - start.y) / max(1, canvasSize.height)
        )
    }

    static func allowsInteraction(
        kind: DragMode.Kind,
        isScreenCropEditingEnabled: Bool,
        allowsCameraCropInteraction: Bool,
        allowsLayerInteraction: Bool
    ) -> Bool {
        switch kind {
        case .screenCropMove, .screenCropResize:
            return isScreenCropEditingEnabled
        case .cropMove, .cropResize:
            return allowsCameraCropInteraction
        case .move, .resize:
            return allowsLayerInteraction
        }
    }

    enum Tick: Equatable {
        case layerFrame(CGRect)
        case beginScreenCropPan(CGRect)
        case cameraCropMove
        case cameraCropResize(ResizeAnchor)
        case screenCropMove
        case screenCropResize(ResizeAnchor)
    }

    struct TickRequest {
        let kind: DragMode.Kind
        let layer: SceneLayerKind
        let startFrame: CGRect
        let delta: CGPoint
        let screenContentMode: CameraContentMode
    }

    static func tick(_ request: TickRequest) -> Tick {
        switch request.kind {
        case .move:
            var frame = request.startFrame
            frame.origin.x += request.delta.x
            frame.origin.y += request.delta.y
            if PreviewStageEditing.shouldBeginConstrainedScreenCropPan(.init(
                layer: request.layer,
                contentMode: request.screenContentMode,
                startFrame: request.startFrame,
                proposedFrame: frame
            )) {
                return .beginScreenCropPan(frame)
            }
            return .layerFrame(frame)
        case .resize(let anchor):
            return .layerFrame(SceneLayerResizing.resized(
                request.startFrame,
                delta: request.delta,
                anchor: anchor,
                aspectRatio: anchor.keepsAspectRatio
                    ? request.startFrame.width / max(0.01, request.startFrame.height)
                    : nil
            ))
        case .cropMove:
            return .cameraCropMove
        case .cropResize(let anchor):
            return .cameraCropResize(anchor)
        case .screenCropMove:
            return .screenCropMove
        case .screenCropResize(let anchor):
            return .screenCropResize(anchor)
        }
    }

    enum BeginCursor: Equatable {
        case crop(DragMode.Kind)
        case resize(ResizeAnchor)
        case closedHand
        case none
    }

    enum Begin: Equatable {
        case ignore
        case background
        case select(SceneLayerKind, drag: DragMode?, cursor: BeginCursor)
    }

    struct BeginRequest {
        var hit: PreviewStageEditing.MouseDownHit
        var location: CGPoint
        var selectedLayer: SceneLayerKind
        var canEditLayer: Bool
        var canBeginScreenCropPan: Bool
        var screenCropFrame: CGRect
        var cameraNormalizedFrame: CGRect
        var layerSelectionFrame: CGRect
        var layerNormalizedSelection: CGRect
        var layerNormalizedFrame: CGRect
        var cameraCropAmount: CGPoint
        var cameraCropPosition: CGPoint
        var activeCameraCropAmount: CGPoint
        var activeCameraCropPosition: CGPoint
    }

    static func begin(_ request: BeginRequest) -> Begin {
        switch request.hit {
        case .ignore:
            return .ignore
        case .background:
            return .background
        case .screenCrop(let mode):
            return .select(
                .screen,
                drag: DragMode(
                    kind: mode,
                    layer: .screen,
                    startPoint: request.location,
                    startFrame: request.screenCropFrame,
                    startCropAmount: request.cameraCropAmount,
                    startCropPosition: request.cameraCropPosition
                ),
                cursor: .crop(mode)
            )
        case .cameraCrop(let mode):
            return .select(
                .camera,
                drag: DragMode(
                    kind: mode,
                    layer: .camera,
                    startPoint: request.location,
                    startFrame: request.cameraNormalizedFrame,
                    startCropAmount: request.activeCameraCropAmount,
                    startCropPosition: request.activeCameraCropPosition
                ),
                cursor: .crop(mode)
            )
        case .resize(let layer, let anchor):
            return .select(
                layer,
                drag: DragMode(
                    kind: .resize(anchor),
                    layer: layer,
                    startPoint: request.location,
                    startFrame: request.layerNormalizedSelection,
                    startCropAmount: request.cameraCropAmount,
                    startCropPosition: request.cameraCropPosition
                ),
                cursor: .resize(anchor)
            )
        case .layer(let layer):
            guard request.canEditLayer || request.canBeginScreenCropPan else {
                return .select(layer, drag: nil, cursor: .none)
            }
            let wasSelected = layer == request.selectedLayer
            if wasSelected, let anchor = PreviewStageEditing.resizeAnchor(
                at: request.location,
                in: request.layerSelectionFrame
            ) {
                return .select(
                    layer,
                    drag: DragMode(
                        kind: .resize(anchor),
                        layer: layer,
                        startPoint: request.location,
                        startFrame: request.layerNormalizedSelection,
                        startCropAmount: request.cameraCropAmount,
                        startCropPosition: request.cameraCropPosition
                    ),
                    cursor: .resize(anchor)
                )
            }
            return .select(
                layer,
                drag: DragMode(
                    kind: .move,
                    layer: layer,
                    startPoint: request.location,
                    startFrame: request.layerNormalizedFrame,
                    startCropAmount: request.cameraCropAmount,
                    startCropPosition: request.cameraCropPosition
                ),
                cursor: .closedHand
            )
        }
    }

    static func apply(_ cursor: BeginCursor) {
        switch cursor {
        case .crop(let mode):
            PreviewStageCursors.cursor(for: mode).set()
        case .resize(let anchor):
            anchor.cursor.set()
        case .closedHand:
            NSCursor.closedHand.set()
        case .none:
            break
        }
    }

    static func dragCursor(for kind: DragMode.Kind) -> NSCursor {
        switch kind {
        case .move, .cropMove, .screenCropMove:
            return .closedHand
        case .resize(let anchor), .cropResize(let anchor), .screenCropResize(let anchor):
            return anchor.cursor
        }
    }
}
