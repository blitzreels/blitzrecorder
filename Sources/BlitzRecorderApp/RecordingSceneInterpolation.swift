import CoreGraphics

extension RecordingScene {
    func interpolated(to target: RecordingScene, progress: CGFloat) -> RecordingScene {
        let progress = min(1, max(0, progress))
        let enabledSources = progress < 1 ? enabledSources.union(target.enabledSources) : target.enabledSources
        var scene = RecordingScene(
            enabledSources: enabledSources,
            sceneLayout: steadyLayout(to: target, progress: progress),
            cameraFeeds: progress < 0.5 ? cameraFeeds : target.cameraFeeds,
            screenSourceGeometry: progress < 1 ? screenSourceGeometry : target.screenSourceGeometry,
            screenCropAmount: screenCropAmount.interpolated(to: target.screenCropAmount, progress: progress),
            screenCropPosition: screenCropPosition.interpolated(to: target.screenCropPosition, progress: progress),
            cameraCropAmount: cameraCropAmount.interpolated(to: target.cameraCropAmount, progress: progress),
            cameraCropPosition: cameraCropPosition.interpolated(to: target.cameraCropPosition, progress: progress),
            canvasBackgroundStyle: progress < 1 ? canvasBackgroundStyle : target.canvasBackgroundStyle,
            canvasBackgroundAnimated: progress < 1 ? canvasBackgroundAnimated : target.canvasBackgroundAnimated,
            canvasPadding: canvasPadding + (target.canvasPadding - canvasPadding) * progress,
            screenCornerRadius: screenCornerRadius + (target.screenCornerRadius - screenCornerRadius) * progress,
            screenShadowEnabled: progress < 1 ? screenShadowEnabled : target.screenShadowEnabled,
            screenContentMode: progress < 1 ? screenContentMode : target.screenContentMode,
            cameraContentMode: progress < 1 ? cameraContentMode : target.cameraContentMode,
            cameraFramePadding: 0,
            cameraShadowEnabled: progress < 1 ? cameraShadowEnabled : target.cameraShadowEnabled,
            cameraCornerRadius: cameraCornerRadius + (target.cameraCornerRadius - cameraCornerRadius) * progress,
            sourceOpacities: interpolatedSourceOpacities(to: target, sources: enabledSources, progress: progress)
        )
        scene.secondCameraCropAmount = secondCameraCropAmount.interpolated(to: target.secondCameraCropAmount, progress: progress)
        scene.secondCameraCropPosition = secondCameraCropPosition.interpolated(
            to: target.secondCameraCropPosition, progress: progress)
        return scene
    }

    /// The layout between two scenes. A layer that is leaving fades out where it was, and one that is arriving fades
    /// in where it will be: a hidden layer keeps a stale frame (often the full canvas), and sliding toward it made
    /// the screen balloon behind the cameras.
    private func steadyLayout(to target: RecordingScene, progress: CGFloat) -> SceneLayout {
        let layout = sceneLayout.interpolated(to: target.sceneLayout, progress: progress)
        func frame(_ source: CaptureSource, moving: CGRect, from start: CGRect, to end: CGRect) -> CGRect {
            switch (enabledSources.contains(source), target.enabledSources.contains(source)) {
            case (true, false): start
            case (false, true): end
            default: moving
            }
        }
        return SceneLayout(
            screenFrame: frame(.screen, moving: layout.screenFrame,
                               from: sceneLayout.screenFrame, to: target.sceneLayout.screenFrame),
            cameraFrame: frame(.camera, moving: layout.cameraFrame,
                               from: sceneLayout.cameraFrame, to: target.sceneLayout.cameraFrame),
            layerOrder: layout.layerOrder,
            cameraMask: layout.cameraMask,
            secondCameraFrame: layout.secondCameraFrame
        )
    }

    private func interpolatedSourceOpacities(
        to target: RecordingScene,
        sources: Set<CaptureSource>,
        progress: CGFloat
    ) -> [CaptureSource: CGFloat] {
        var opacities: [CaptureSource: CGFloat] = [:]
        for source in sources {
            let startOpacity = sourceOpacity(for: source)
            let targetOpacity = target.sourceOpacity(for: source)
            let opacity = startOpacity + (targetOpacity - startOpacity) * progress
            if abs(opacity - 1) > 0.001 {
                opacities[source] = min(1, max(0, opacity))
            }
        }
        return opacities
    }
}

extension SceneLayout {
    func interpolated(to target: SceneLayout, progress: CGFloat) -> SceneLayout {
        let progress = min(1, max(0, progress))
        return SceneLayout(
            screenFrame: screenFrame.interpolated(to: target.screenFrame, progress: progress),
            cameraFrame: cameraFrame.interpolated(to: target.cameraFrame, progress: progress),
            layerOrder: progress <= 0 ? layerOrder : target.layerOrder,
            cameraMask: progress <= 0
                ? cameraMask
                : (progress >= 1 || cameraMask == target.cameraMask ? target.cameraMask : .rectangle),
            secondCameraFrame: interpolatedSecondCameraFrame(to: target, progress: progress)
        )
    }

    /// A second camera that appears or leaves grows from or shrinks into the first camera's frame.
    private func interpolatedSecondCameraFrame(to target: SceneLayout, progress: CGFloat) -> CGRect? {
        switch (secondCameraFrame, target.secondCameraFrame) {
        case (nil, nil): return nil
        case let (start?, end?): return start.interpolated(to: end, progress: progress)
        case let (nil, end?): return progress <= 0 ? nil : cameraFrame.interpolated(to: end, progress: progress)
        case let (start?, nil): return progress >= 1 ? nil : start.interpolated(to: target.cameraFrame, progress: progress)
        }
    }
}

private extension CGRect {
    func interpolated(to target: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: minX + (target.minX - minX) * progress,
            y: minY + (target.minY - minY) * progress,
            width: width + (target.width - width) * progress,
            height: height + (target.height - height) * progress
        )
    }
}

private extension CGPoint {
    func interpolated(to target: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (target.x - x) * progress,
            y: y + (target.y - y) * progress
        )
    }
}
