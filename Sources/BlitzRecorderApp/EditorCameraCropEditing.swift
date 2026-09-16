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

enum EditorCameraCropSession {
    static func begin(eventIndex: Int, sceneEvents: [RecordingSceneEvent]) -> EditorCameraCropDraft? {
        guard sceneEvents.indices.contains(eventIndex),
              sceneEvents[eventIndex].scene.enabledSources.contains(.camera) else {
            return nil
        }
        let scene = sceneEvents[eventIndex].scene
        return EditorCameraCropDraft(
            eventIndex: eventIndex,
            originalScene: scene,
            scene: scene
        )
    }

    static func applying(
        _ change: EditorCameraCropInteractionChange,
        to draft: EditorCameraCropDraft,
        renderSize: CGSize,
        sourceAspectRatio: CGFloat
    ) -> EditorCameraCropDraft? {
        guard renderSize.width > 0, renderSize.height > 0 else { return nil }
        let renderGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: renderSize),
            scene: draft.scene,
            origin: .upperLeft
        )
        let cropGeometry = CameraCropGeometry(
            renderGeometry: renderGeometry,
            sourceAspectRatio: sourceAspectRatio
        )
        let startCrop = cropGeometry.cropFrame(
            amount: change.startControl.amount,
            position: change.startControl.position
        )
        let crop: CGRect
        switch change.kind {
        case .move:
            crop = cropGeometry.movedCropFrame(startCrop, delta: change.delta)
        case .resize(let anchor):
            crop = cropGeometry.resizedCropFrame(startCrop, delta: change.delta, anchor: anchor)
        }
        guard let control = cropGeometry.control(for: crop) else { return nil }
        var draft = draft
        draft.scene.cameraCropAmount = control.amount
        draft.scene.cameraCropPosition = control.position
        return draft
    }

    static func resetting(_ draft: EditorCameraCropDraft) -> EditorCameraCropDraft {
        var draft = draft
        draft.scene.cameraCropAmount = .zero
        draft.scene.cameraCropPosition = .zero
        return draft
    }

    struct Commit {
        let eventIndex: Int
        let amount: CGPoint
        let position: CGPoint
    }

    static func commit(_ draft: EditorCameraCropDraft) -> Commit {
        Commit(
            eventIndex: draft.eventIndex,
            amount: draft.scene.cameraCropAmount,
            position: draft.scene.cameraCropPosition
        )
    }
}
