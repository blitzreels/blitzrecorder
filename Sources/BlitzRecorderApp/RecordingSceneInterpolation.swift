import CoreGraphics

extension RecordingScene {
    func interpolated(to target: RecordingScene, progress: CGFloat) -> RecordingScene {
        let progress = min(1, max(0, progress))
        let enabledSources = progress < 1 ? enabledSources.union(target.enabledSources) : target.enabledSources
        return RecordingScene(
            enabledSources: enabledSources,
            sceneLayout: sceneLayout.interpolated(to: target.sceneLayout, progress: progress),
            screenSourceGeometry: progress < 1 ? screenSourceGeometry : target.screenSourceGeometry,
            cameraCropAmount: cameraCropAmount.interpolated(to: target.cameraCropAmount, progress: progress),
            cameraCropPosition: cameraCropPosition.interpolated(to: target.cameraCropPosition, progress: progress),
            canvasBackgroundStyle: progress < 1 ? canvasBackgroundStyle : target.canvasBackgroundStyle,
            canvasBackgroundAnimated: progress < 1 ? canvasBackgroundAnimated : target.canvasBackgroundAnimated,
            canvasPadding: canvasPadding + (target.canvasPadding - canvasPadding) * progress,
            sourceOpacities: interpolatedSourceOpacities(to: target, sources: enabledSources, progress: progress)
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
            layerOrder: progress <= 0 ? layerOrder : target.layerOrder
        )
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
