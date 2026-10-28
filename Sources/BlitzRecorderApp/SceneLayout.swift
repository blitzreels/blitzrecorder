import CoreGraphics

struct SceneLayout: Equatable {
    var screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var cameraFrame: CGRect = CGRect(x: 0, y: 0.046796875, width: 1, height: 0.31640625)
    var layerOrder: [SceneLayerKind] = [.screen, .camera]
    var cameraMask: SceneCameraMask = .rectangle
    /// The second camera's frame in two-camera layouts; nil when the scene shows one camera.
    var secondCameraFrame: CGRect?

    func frame(for kind: SceneLayerKind) -> CGRect {
        switch kind {
        case .screen: return screenFrame
        case .camera: return cameraFrame
        case .secondCamera: return secondCameraFrame ?? .zero
        }
    }

    mutating func setFrame(_ frame: CGRect, for kind: SceneLayerKind) {
        switch kind {
        case .screen: screenFrame = frame
        case .camera: cameraFrame = frame
        case .secondCamera: secondCameraFrame = frame
        }
    }

    /// Back to front, with the second camera right above the first when the scene has one.
    var renderLayerOrder: [SceneLayerKind] {
        guard secondCameraFrame != nil else { return layerOrder }
        var order = layerOrder.filter { $0 != .secondCamera }
        order.insert(.secondCamera, at: (order.firstIndex(of: .camera) ?? order.count - 1) + 1)
        return order
    }

    static func scaledAroundCenter(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let scale = min(1, max(0.1, scale))
        let width = frame.width * scale
        let height = frame.height * scale
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static let maximumSideBySideCameraWidth: CGFloat = 0.6
    static let minimumSideBySideCameraWidth: CGFloat = 0.2

    static func defaultSideBySideCameraWidth(for layout: CaptureLayout) -> CGFloat {
        min(0.4, portraitCameraWidth(for: layout))
    }

    static func portraitCameraWidth(for layout: CaptureLayout) -> CGFloat {
        (9.0 / 16.0) / layout.aspectRatio
    }

    static func clampedSideBySideCameraWidth(_ width: CGFloat) -> CGFloat {
        min(maximumSideBySideCameraWidth, max(minimumSideBySideCameraWidth, width))
    }

    struct SideBySideRequest {
        let cameraWidth: CGFloat
        let cameraSide: SceneCameraSide
    }

    static func sideBySideLayout(_ request: SideBySideRequest) -> SceneLayout {
        let width = clampedSideBySideCameraWidth(request.cameraWidth)
        var sceneLayout = SceneLayout()
        sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: width, height: 1)
        sceneLayout.screenFrame = CGRect(x: width, y: 0, width: 1 - width, height: 1)
        sceneLayout.layerOrder = [.screen, .camera]
        return sceneLayout.withCameraSide(request.cameraSide)
    }

    var sideBySideCameraWidth: CGFloat? {
        guard cameraSide != nil else { return nil }
        return cameraFrame.width
    }
    static let cameraAspectRatio: CGFloat = 16.0 / 9.0
    static let defaultScreenAspectRatio: CGFloat = 16.0 / 9.0
    static let defaultScreenSplitHeight: CGFloat = 0.5
    static let minimumScreenSplitHeight: CGFloat = 0.3
    static let maximumScreenSplitHeight: CGFloat = 0.75
    static let defaultCameraInsetSize: CGFloat = 0.28
    static let minimumCameraInsetSize: CGFloat = 0.18
    static let maximumCameraInsetSize: CGFloat = 0.52
    static let cameraInsetMargin: CGFloat = 0.035

    static func defaultCameraInsetSize(for layout: CaptureLayout) -> CGFloat {
        switch layout {
        case .horizontal, .square:
            return defaultCameraInsetSize
        case .vertical:
            return maximumCameraInsetSize(for: layout)
        }
    }

    static func maximumCameraInsetSize(for layout: CaptureLayout) -> CGFloat {
        switch layout {
        case .horizontal, .square:
            return maximumCameraInsetSize
        case .vertical:
            return max(minimumCameraInsetSize, 1 - cameraInsetMargin * 2)
        }
    }

    static func screenSplitLayout(
        screenHeight: CGFloat,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio
    ) -> SceneLayout {
        let screenHeight = clampedScreenSplitHeight(screenHeight)

        var sceneLayout = SceneLayout()
        sceneLayout.screenFrame = CGRect(
            x: 0,
            y: 1 - screenHeight,
            width: 1,
            height: screenHeight
        )
        sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1 - screenHeight)
        return sceneLayout
    }

    static func cameraInsetLayout(
        for layout: CaptureLayout,
        alignment: CameraInsetAlignment = .bottomRight,
        shape: CameraInsetShape = .landscape,
        size: CGFloat? = nil,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio,
        cameraAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> SceneLayout {
        let size = size ?? defaultCameraInsetSize(for: layout)
        var sceneLayout = SceneLayout()
        sceneLayout.screenFrame = canvasFillingFrame(
            sourceAspectRatio: screenAspectRatio,
            canvasAspectRatio: layout.aspectRatio
        )
        sceneLayout.cameraFrame = cameraInsetFrame(
            for: layout,
            alignment: alignment,
            shape: shape,
            size: size,
            sourceAspectRatio: cameraAspectRatio
        )
        sceneLayout.layerOrder = [.screen, .camera]
        return sceneLayout
    }

    static func cameraInsetFrame(
        for layout: CaptureLayout,
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat,
        sourceAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> CGRect {
        let availableWidth = max(0.001, 1 - cameraInsetMargin * 2)
        let availableHeight = max(0.001, 1 - cameraInsetMargin * 2)
        let dominantSize = min(maximumCameraInsetSize(for: layout), max(minimumCameraInsetSize, size))
        let canvasAspectRatio = layout.aspectRatio
        let shapeAspectRatio = shape.aspectRatio(forSource: sourceAspectRatio)

        var width: CGFloat
        var height: CGFloat
        switch shape {
        case .landscape, .circle:
            width = dominantSize
            height = width * canvasAspectRatio / shapeAspectRatio
        case .portrait:
            height = dominantSize
            width = height * shapeAspectRatio / canvasAspectRatio
        }

        let fitScale = min(1, availableWidth / width, availableHeight / height)
        width *= fitScale
        height *= fitScale

        let x: CGFloat
        switch alignment {
        case .bottomLeft:
            x = cameraInsetMargin
        case .bottomRight:
            x = 1 - cameraInsetMargin - width
        }

        return CGRect(x: x, y: cameraInsetMargin, width: width, height: height)
    }

    static func cameraInsetAlignment(for frame: CGRect) -> CameraInsetAlignment {
        frame.standardized.midX < 0.5 ? .bottomLeft : .bottomRight
    }

    static func isCameraInsetFrame(_ frame: CGRect) -> Bool {
        let frame = frame.standardized
        guard frame.width > 0.0001, frame.height > 0.0001 else { return false }
        guard abs(frame.minY - cameraInsetMargin) < 0.005 else { return false }
        let leftAnchored = abs(frame.minX - cameraInsetMargin) < 0.005
        let rightAnchored = abs(frame.maxX - (1 - cameraInsetMargin)) < 0.005
        return leftAnchored || rightAnchored
    }

    static func cameraInsetShape(for frame: CGRect, in layout: CaptureLayout) -> CameraInsetShape {
        cameraInsetAspectRatio(for: frame, in: layout) < 1 ? .portrait : .landscape
    }

    static func cameraInsetSize(for frame: CGRect, in layout: CaptureLayout) -> CGFloat {
        cameraInsetSize(CameraInsetSizeRequest(
            frame: frame,
            shape: cameraInsetShape(for: frame, in: layout),
            layout: layout
        ))
    }

    func cameraInsetShape(in layout: CaptureLayout) -> CameraInsetShape {
        cameraMask == .circle ? .circle : Self.cameraInsetShape(for: cameraFrame, in: layout)
    }

    func cameraInsetSize(in layout: CaptureLayout) -> CGFloat {
        Self.cameraInsetSize(CameraInsetSizeRequest(
            frame: cameraFrame,
            shape: cameraInsetShape(in: layout),
            layout: layout
        ))
    }

    private struct CameraInsetSizeRequest {
        let frame: CGRect
        let shape: CameraInsetShape
        let layout: CaptureLayout
    }

    private static func cameraInsetSize(_ request: CameraInsetSizeRequest) -> CGFloat {
        let frame = request.frame.standardized
        let size: CGFloat
        switch request.shape {
        case .landscape, .circle:
            size = frame.width
        case .portrait:
            size = frame.height
        }
        return min(maximumCameraInsetSize(for: request.layout), max(minimumCameraInsetSize, size))
    }

    private static func cameraInsetAspectRatio(for frame: CGRect, in layout: CaptureLayout) -> CGFloat {
        let frame = frame.standardized
        guard frame.width > 0, frame.height > 0 else {
            return CameraInsetShape.landscape.aspectRatio
        }
        return (frame.width / frame.height) * layout.aspectRatio
    }

    static func clampedScreenSplitHeight(_ height: CGFloat) -> CGFloat {
        min(maximumScreenSplitHeight, max(minimumScreenSplitHeight, height))
    }

    static func canvasFillingFrame(sourceAspectRatio: CGFloat, canvasAspectRatio: CGFloat) -> CGRect {
        guard sourceAspectRatio > 0, canvasAspectRatio > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let sourceARInCanvasCoords = sourceAspectRatio / canvasAspectRatio
        if sourceARInCanvasCoords >= 1 {
            let w = sourceARInCanvasCoords
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else {
            let h = 1 / sourceARInCanvasCoords
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
    }

    static func fittedSourceFrame(
        sourceAspectRatio: CGFloat,
        canvasAspectRatio: CGFloat,
        in container: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> CGRect {
        guard sourceAspectRatio > 0,
              canvasAspectRatio > 0,
              !container.isEmpty else {
            return container
        }

        let containerAspectRatio = (container.width / container.height) * canvasAspectRatio
        let width: CGFloat
        let height: CGFloat
        if containerAspectRatio > sourceAspectRatio {
            height = container.height
            width = height * sourceAspectRatio / canvasAspectRatio
        } else {
            width = container.width
            height = width * canvasAspectRatio / sourceAspectRatio
        }

        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        )
    }

    var screenSplitHeight: CGFloat? {
        let screen = screenFrame.standardized
        let camera = cameraFrame.standardized
        guard almostEqual(camera.minX, 0),
              almostEqual(camera.minY, 0),
              almostEqual(camera.width, 1),
              almostEqual(screen.maxY, 1),
              almostEqual(screen.minY, camera.maxY),
              screen.height >= SceneLayout.minimumScreenSplitHeight,
              screen.height <= SceneLayout.maximumScreenSplitHeight else {
            return nil
        }
        return screen.height
    }

    private func almostEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}

enum SceneCameraSide: Equatable {
    case left
    case right
}

extension SceneLayout {
    var cameraSide: SceneCameraSide? {
        let sideBySide = screenFrame.height >= 0.999
            && cameraFrame.height >= 0.999
            && (cameraFrame.maxX <= screenFrame.minX + 0.001 || screenFrame.maxX <= cameraFrame.minX + 0.001)
        guard sideBySide else { return nil }
        return cameraFrame.midX < screenFrame.midX ? .left : .right
    }

    func withCameraSide(_ side: SceneCameraSide?) -> SceneLayout {
        guard let side, let current = cameraSide, current != side else { return self }
        var mirrored = self
        mirrored.screenFrame = Self.mirroredHorizontally(screenFrame)
        mirrored.cameraFrame = Self.mirroredHorizontally(cameraFrame)
        return mirrored
    }

    private static func mirroredHorizontally(_ frame: CGRect) -> CGRect {
        CGRect(x: 1 - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }
}

extension SceneLayout {
    private func visibleFrames(_ visibleSources: Set<CaptureSource>) -> [SceneLayerKind: CGRect] {
        resolvedItems(enabledSources: visibleSources, fillsCanvasWhenOnlyVideoSource: false)
            .reduce(into: [SceneLayerKind: CGRect]()) { $0[$1.kind] = $1.normalizedFrame.standardized }
    }

    func cameraFloats(visibleSources: Set<CaptureSource>) -> Bool {
        let frames = visibleFrames(visibleSources)
        guard let camera = frames[.camera] else { return false }
        if Self.isCameraInsetFrame(camera) { return true }
        guard let screen = frames[.screen] else { return false }
        return camera.liesMostlyInside(screen)
    }

    func arrangementName(visibleSources: Set<CaptureSource>) -> String {
        let frames = visibleFrames(visibleSources)
        if secondCameraFrame != nil, frames[.camera] != nil {
            return frames[.screen] == nil ? "Two Cameras" : "Screen + Two Cameras"
        }
        switch (frames[.screen], frames[.camera]) {
        case (_?, _?):
            return cameraFloats(visibleSources: visibleSources) ? "Camera Inset" : "Screen + Camera"
        case (_?, nil):
            return "Screen"
        case (nil, _?):
            return "Camera"
        case (nil, nil):
            return "Empty"
        }
    }
}
