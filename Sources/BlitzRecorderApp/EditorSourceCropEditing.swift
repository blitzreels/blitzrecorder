import CoreGraphics

struct EditorSourceCropPresentationRequest {
    let kind: SceneLayerKind
    let containerSize: CGSize
    let renderSize: CGSize
    let scene: RecordingScene
    let sourceAspectRatio: CGFloat
}

struct EditorSourceCropPresentation {
    let canvasFrame: CGRect
    let sourceFrame: CGRect
    let cropFrame: CGRect
    let pointsPerRenderUnit: CGFloat

    static func make(_ request: EditorSourceCropPresentationRequest) -> EditorSourceCropPresentation? {
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
        let cropGeometry = LayerCropGeometry(
            kind: request.kind,
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

        return EditorSourceCropPresentation(
            canvasFrame: canvasFrame,
            sourceFrame: mapped(cropGeometry.sourceFrame),
            cropFrame: mapped(cropGeometry.cropFrame(
                amount: request.scene.cropAmount(for: request.kind),
                position: request.scene.cropPosition(for: request.kind)
            )),
            pointsPerRenderUnit: scale
        )
    }
}

struct EditorSourceCropDraft {
    let kind: SceneLayerKind
    let eventIndex: Int
    let originalScene: RecordingScene
    var scene: RecordingScene
}

extension RecordingScene {
    func cropAmount(for kind: SceneLayerKind) -> CGPoint {
        sourceCropAmount(for: kind)
    }

    func cropPosition(for kind: SceneLayerKind) -> CGPoint {
        sourceCropPosition(for: kind)
    }

    /// Cropping always fills the frame, so the chosen area is exactly what shows.
    mutating func setCrop(_ control: LayerCropControl, for kind: SceneLayerKind) {
        switch kind {
        case .screen:
            screenCropAmount = control.amount
            screenCropPosition = control.position
            screenContentMode = .fill
        case .camera:
            cameraCropAmount = control.amount
            cameraCropPosition = control.position
            cameraContentMode = .fill
        case .secondCamera:
            secondCameraCropAmount = control.amount
            secondCameraCropPosition = control.position
            cameraContentMode = .fill
        }
    }
}

enum EditorSourceCropSession {
    struct BeginRequest {
        let kind: SceneLayerKind
        let eventIndex: Int
        let sceneEvents: [RecordingSceneEvent]
    }

    static func begin(_ request: BeginRequest) -> EditorSourceCropDraft? {
        let source: CaptureSource = request.kind == .screen ? .screen : .camera
        guard request.sceneEvents.indices.contains(request.eventIndex),
              request.sceneEvents[request.eventIndex].scene.enabledSources.contains(source) else {
            return nil
        }
        let original = request.sceneEvents[request.eventIndex].scene
        var scene = original
        scene.setCrop(.init(amount: original.cropAmount(for: request.kind),
                            position: original.cropPosition(for: request.kind)), for: request.kind)
        return EditorSourceCropDraft(kind: request.kind, eventIndex: request.eventIndex, originalScene: original, scene: scene)
    }

    struct ChangeRequest {
        let change: EditorSourceCropInteractionChange
        let draft: EditorSourceCropDraft
        let renderSize: CGSize
        let sourceAspectRatio: CGFloat
    }

    static func applying(_ request: ChangeRequest) -> EditorSourceCropDraft? {
        guard request.renderSize.width > 0, request.renderSize.height > 0 else { return nil }
        let renderGeometry = SceneRenderGeometry(
            canvas: CGRect(origin: .zero, size: request.renderSize),
            scene: request.draft.scene,
            origin: .upperLeft
        )
        let cropGeometry = LayerCropGeometry(
            kind: request.draft.kind,
            renderGeometry: renderGeometry,
            sourceAspectRatio: request.sourceAspectRatio
        )
        let change = request.change
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
        var draft = request.draft
        draft.scene.setCrop(control, for: draft.kind)
        return draft
    }

    static func resetting(_ draft: EditorSourceCropDraft) -> EditorSourceCropDraft {
        var draft = draft
        draft.scene.setCrop(.init(amount: .zero, position: .zero), for: draft.kind)
        return draft
    }

    struct Commit {
        let kind: SceneLayerKind
        let eventIndex: Int
        let control: LayerCropControl

        func apply(to scene: inout RecordingScene) {
            scene.setCrop(control, for: kind)
        }
    }

    static func commit(_ draft: EditorSourceCropDraft) -> Commit {
        Commit(
            kind: draft.kind,
            eventIndex: draft.eventIndex,
            control: .init(amount: draft.scene.cropAmount(for: draft.kind),
                           position: draft.scene.cropPosition(for: draft.kind))
        )
    }
}
