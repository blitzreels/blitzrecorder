import AppKit
import QuartzCore

extension PreviewStageView {
    private func updateBackgroundPixelSize() -> (width: Int, height: Int)? {
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 2
        canvasBackgroundLayer.contentsScale = scale
        let width = Int((canvasBackgroundLayer.bounds.width * scale).rounded(.up))
        let height = Int((canvasBackgroundLayer.bounds.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    func refreshCanvasBackground() {
        guard let pixelSize = updateBackgroundPixelSize() else { return }
        let key = BackgroundRenderKey(style: canvasBackgroundStyle, width: pixelSize.width, height: pixelSize.height)
        if renderedBackgroundKey == key {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let appearance = canvasBackgroundStyle.appearance
        canvasBackgroundLayer.backgroundColor = appearance.solidCGColor
        CATransaction.commit()
        guard requestedBackgroundKey != key else { return }
        requestedBackgroundKey = key
        backgroundRenderTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderCanvasBackground(key)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundRenderTimer = timer
    }

    func renderCanvasBackground(_ key: BackgroundRenderKey) {
        guard requestedBackgroundKey == key,
              !canvasBackgroundAnimated || !canvasBackgroundStyle.supportsBackgroundAnimation else { return }
        backgroundRenderTimer = nil
        backgroundAnimationQueue.async {
            let image = key.style.appearance.renderCGImage(pixelWidth: key.width, pixelHeight: key.height)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestedBackgroundKey == key else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.canvasBackgroundLayer.contents = image
                CATransaction.commit()
                self.renderedBackgroundKey = key
                self.requestedBackgroundKey = nil
            }
        }
    }

    func invalidateCanvasBackgroundRender() {
        backgroundRenderTimer?.invalidate()
        backgroundRenderTimer = nil
        requestedBackgroundKey = nil
        renderedBackgroundKey = nil
    }

    func updateBackgroundAnimation() {
        let shouldAnimate = canvasBackgroundAnimated
            && canvasBackgroundStyle.supportsBackgroundAnimation
            && isStudioOnScreen
            && window?.occlusionState.contains(.visible) == true
            && !canvasBackgroundLayer.bounds.isEmpty
        if shouldAnimate {
            guard backgroundAnimationTimer == nil else { return }
            backgroundAnimationStart = CACurrentMediaTime()
            let timer = Timer(timeInterval: Self.animatedBackgroundFrameInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.renderAnimatedBackgroundFrame()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            backgroundAnimationTimer = timer
            renderAnimatedBackgroundFrame()
        } else {
            // A paused animation keeps its last frame; only an animation that was turned off, or a still
            // background that has not been drawn, needs the still picture drawn.
            let wasAnimating = backgroundAnimationTimer != nil
            backgroundAnimationTimer?.invalidate()
            backgroundAnimationTimer = nil
            canvasBackgroundLayer.removeAnimation(forKey: "drift")
            if wasAnimating && canvasBackgroundAnimated { return }
            if wasAnimating { renderedBackgroundKey = nil }
            refreshCanvasBackground()
        }
    }

    /// The drift moves a few points per frame, so frames are drawn four times a second and Core Animation
    /// cross-fades between them on the GPU.
    static let animatedBackgroundFrameInterval: CFTimeInterval = 0.25

    /// Moving frames render at point size, a quarter of the Retina pixels: the soft drifting gradients scale up
    /// without visible loss, and the still background keeps full resolution. Each frame shows where the drift will
    /// be when its cross-fade ends.
    func renderAnimatedBackgroundFrame() {
        guard canvasBackgroundAnimated, canvasBackgroundStyle.supportsBackgroundAnimation, !isRenderingAnimatedFrame else { return }
        guard let pixelSize = updateBackgroundPixelSize() else { return }
        let backingScale = max(1, window?.backingScaleFactor ?? 2)
        let frameWidth = max(1, Int((CGFloat(pixelSize.width) / backingScale).rounded(.up)))
        let frameHeight = max(1, Int((CGFloat(pixelSize.height) / backingScale).rounded(.up)))
        let style = canvasBackgroundStyle
        let loop = CanvasAppearance.animationLoopDuration
        let interval = Self.animatedBackgroundFrameInterval
        let phase = ((CACurrentMediaTime() + interval - backgroundAnimationStart) / loop).truncatingRemainder(dividingBy: 1)
        isRenderingAnimatedFrame = true
        backgroundAnimationQueue.async { [weak self] in
            let image = style.appearance.renderCGImage(pixelWidth: frameWidth, pixelHeight: frameHeight, animationPhase: phase)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRenderingAnimatedFrame = false
                guard self.canvasBackgroundAnimated,
                      self.canvasBackgroundStyle == style,
                      self.canvasBackgroundStyle.supportsBackgroundAnimation else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if let previous = self.canvasBackgroundLayer.contents {
                    let fade = CABasicAnimation(keyPath: "contents")
                    fade.fromValue = previous
                    fade.toValue = image
                    fade.duration = interval
                    self.canvasBackgroundLayer.add(fade, forKey: "drift")
                }
                self.canvasBackgroundLayer.contents = image
                CATransaction.commit()
            }
        }
    }

    func updateCanvasSelectionAffordance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isBackgroundLayerSelected {
            canvasBackgroundLayer.borderColor = resolvedCGColor(Self.backgroundSelectionColor)
            canvasBackgroundLayer.borderWidth = 2
        } else {
            canvasBackgroundLayer.borderColor = resolvedCGColor(BlitzColors.strongStroke.nsColor)
            canvasBackgroundLayer.borderWidth = 1
        }
        CATransaction.commit()
    }

    private static var backgroundSelectionColor: NSColor { BlitzThemeStore.shared.accent.nsAccent.withAlphaComponent(0.95) }
}
