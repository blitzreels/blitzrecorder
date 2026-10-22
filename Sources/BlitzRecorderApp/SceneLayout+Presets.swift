import CoreGraphics

extension SceneLayout {
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
        case .screenTop50, .equalSplit:
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
        case .screenInset:
            return screenInsetLayout(.init(layout: .vertical, screenAspectRatio: screenAspectRatio))
        case .webcamLeft, .cameraRight, .webcamFullscreen:
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
            return sideBySideLayout(.init(
                cameraWidth: defaultSideBySideCameraWidth(for: request.layout),
                cameraSide: .left
            ))
        case .cameraRight:
            return landscapeStylePresetLayout(.init(
                preset: .webcamLeft,
                layout: request.layout,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )).withCameraSide(.right)
        case .equalSplit:
            return SceneLayout(
                screenFrame: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
                cameraFrame: CGRect(x: 0, y: 0, width: 0.5, height: 1)
            )
        case .screenInset:
            return screenInsetLayout(.init(layout: request.layout, screenAspectRatio: screenAspectRatio))
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

    private struct ScreenInsetRequest {
        let layout: CaptureLayout
        let screenAspectRatio: CGFloat
    }

    private static func screenInsetLayout(_ request: ScreenInsetRequest) -> SceneLayout {
        let container = request.layout == .vertical
            ? CGRect(x: 0.06, y: 0.67, width: 0.88, height: 0.28)
            : CGRect(x: 0.62, y: 0.60, width: 0.34, height: 0.34)
        return SceneLayout(
            screenFrame: fittedSourceFrame(
                sourceAspectRatio: request.screenAspectRatio,
                canvasAspectRatio: request.layout.aspectRatio,
                in: container
            ),
            cameraFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            layerOrder: [.camera, .screen]
        )
    }

    private static func fullWidthSourceHeight(sourceAspectRatio: CGFloat, canvasAspectRatio: CGFloat) -> CGFloat {
        guard sourceAspectRatio > 0, canvasAspectRatio > 0 else { return 0.5 }
        return min(0.65, max(0.2, canvasAspectRatio / sourceAspectRatio))
    }
}
