import CoreGraphics

struct EditorCameraCropPresentationRequest {
    let containerSize: CGSize
    let renderSize: CGSize
    let scene: RecordingScene
    let sourceAspectRatio: CGFloat
}

struct EditorCameraCropPresentation {
    let canvasFrame: CGRect
    let sourceFrame: CGRect
    let cropFrame: CGRect
    let pointsPerRenderUnit: CGFloat

    static func make(_ request: EditorCameraCropPresentationRequest) -> EditorCameraCropPresentation? {
        guard request.containerSize.width > 0,
              request.containerSize.height > 0,
              request.renderSize.width > 0,
              request.renderSize.height > 0,
              request.sourceAspectRatio > 0 else {
            return nil
        }

        let renderCanvas = CGRect(origin: .zero, size: request.renderSize)
        let renderGeometry = SceneRenderGeometry(
            canvas: renderCanvas,
            scene: request.scene,
            origin: .upperLeft
        )
        let cropGeometry = CameraCropGeometry(
            renderGeometry: renderGeometry,
            sourceAspectRatio: request.sourceAspectRatio
        )
        let region = renderCanvas.union(cropGeometry.sourceFrame)
        guard region.width > 0, region.height > 0 else { return nil }

        let scale = min(
            request.containerSize.width / region.width,
            request.containerSize.height / region.height
        )
        let regionOrigin = CGPoint(
            x: (request.containerSize.width - region.width * scale) / 2,
            y: (request.containerSize.height - region.height * scale) / 2
        )
        let canvasFrame = CGRect(
            x: regionOrigin.x - region.minX * scale,
            y: regionOrigin.y - region.minY * scale,
            width: request.renderSize.width * scale,
            height: request.renderSize.height * scale
        )

        func mapped(_ rect: CGRect) -> CGRect {
            CGRect(
                x: canvasFrame.minX + rect.minX * scale,
                y: canvasFrame.minY + rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }

        return EditorCameraCropPresentation(
            canvasFrame: canvasFrame,
            sourceFrame: mapped(cropGeometry.sourceFrame),
            cropFrame: mapped(cropGeometry.cropFrame(
                amount: request.scene.cameraCropAmount,
                position: request.scene.cameraCropPosition
            )),
            pointsPerRenderUnit: scale
        )
    }
}

struct EditorCameraCropDraft {
    let eventIndex: Int
    let originalScene: RecordingScene
    var scene: RecordingScene
}
