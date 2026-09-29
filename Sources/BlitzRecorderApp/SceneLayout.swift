import CoreGraphics

struct SceneLayout: Equatable {
    var screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var cameraFrame: CGRect = CGRect(x: 0, y: 0.046796875, width: 1, height: 0.31640625)
    var layerOrder: [SceneLayerKind] = [.screen, .camera]
    var cameraMask: SceneCameraMask = .rectangle

    func frame(for kind: SceneLayerKind) -> CGRect {
        switch kind {
        case .screen: return screenFrame
        case .camera: return cameraFrame
        }
    }

    mutating func setFrame(_ frame: CGRect, for kind: SceneLayerKind) {
        switch kind {
        case .screen: screenFrame = frame
        case .camera: cameraFrame = frame
        }
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

    static func defaultLayout(
        for layout: CaptureLayout,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio,
        cameraAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> SceneLayout {
        presetLayout(
            .defaultPreset(for: layout),
            for: layout,
            screenAspectRatio: screenAspectRatio,
            cameraAspectRatio: cameraAspectRatio
        )
    }

    static func presetLayout(
        _ preset: ScenePreset,
        for layout: CaptureLayout,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio,
        cameraAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> SceneLayout {
        switch layout {
        case .vertical:
            verticalPresetLayout(preset, screenAspectRatio: screenAspectRatio, cameraAspectRatio: cameraAspectRatio)
        case .horizontal, .square:
            landscapeStylePresetLayout(.init(
                preset: preset,
                layout: layout,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            ))
        }
    }

    private static func verticalPresetLayout(
        _ preset: ScenePreset,
        screenAspectRatio: CGFloat,
        cameraAspectRatio: CGFloat
    ) -> SceneLayout {
        let canvasAR = CaptureLayout.vertical.aspectRatio
        switch preset {
        case .stackedHalves:
            var sceneLayout = SceneLayout()
            let screenHeight = fullWidthSourceHeight(
                sourceAspectRatio: screenAspectRatio,
                canvasAspectRatio: canvasAR
            )
            sceneLayout.screenFrame = CGRect(x: 0, y: 1 - screenHeight, width: 1, height: screenHeight)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1 - screenHeight)
            return sceneLayout
        case .screenTop50:
            return screenSplitLayout(screenHeight: defaultScreenSplitHeight, screenAspectRatio: screenAspectRatio)
        case .screenTop70:
            return screenSplitLayout(screenHeight: 0.7, screenAspectRatio: screenAspectRatio)
        case .screenFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = CGRect(x: 0.455, y: 0.045, width: 0.5, height: 0.25)
            return sceneLayout
        case .cameraInset:
            return cameraInsetLayout(
                for: .vertical,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        case .cameraFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = fittedSourceFrame(
                sourceAspectRatio: screenAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.06, y: 0.67, width: 0.88, height: 0.28)
            )
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamLeft, .webcamFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        case .screenFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        }
    }

    private struct LandscapeStylePresetRequest {
        let preset: ScenePreset
        let layout: CaptureLayout
        let screenAspectRatio: CGFloat
        let cameraAspectRatio: CGFloat
    }

    private static func landscapeStylePresetLayout(_ request: LandscapeStylePresetRequest) -> SceneLayout {
        let preset = request.preset
        let screenAspectRatio = request.screenAspectRatio
        let cameraAspectRatio = request.cameraAspectRatio
        let canvasAR = request.layout.aspectRatio
        switch preset {
        case .stackedHalves:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
            return sceneLayout
        case .screenTop50, .screenTop70:
            return landscapeStylePresetLayout(.init(
                preset: .stackedHalves,
                layout: request.layout,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            ))
        case .screenFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.73, y: 0.05, width: 0.22, height: 0.22)
            )
            return sceneLayout
        case .cameraInset:
            return cameraInsetLayout(
                for: request.layout,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        case .cameraFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = fittedSourceFrame(
                sourceAspectRatio: screenAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.66, y: 0.62, width: 0.3, height: 0.3)
            )
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamLeft:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        case .screenFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR
            )
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        }
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

    private static func fullWidthSourceHeight(sourceAspectRatio: CGFloat, canvasAspectRatio: CGFloat) -> CGFloat {
        guard sourceAspectRatio > 0, canvasAspectRatio > 0 else { return 0.5 }
        return min(0.65, max(0.2, canvasAspectRatio / sourceAspectRatio))
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
