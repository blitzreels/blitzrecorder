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
            && window != nil
            && !canvasBackgroundLayer.bounds.isEmpty
        if shouldAnimate {
            guard backgroundAnimationTimer == nil else { return }
            backgroundAnimationStart = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.renderAnimatedBackgroundFrame()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            backgroundAnimationTimer = timer
            renderAnimatedBackgroundFrame()
        } else {
            backgroundAnimationTimer?.invalidate()
            backgroundAnimationTimer = nil
            renderedBackgroundKey = nil
            refreshCanvasBackground()
        }
    }

    func renderAnimatedBackgroundFrame() {
        guard canvasBackgroundAnimated, canvasBackgroundStyle.supportsBackgroundAnimation, !isRenderingAnimatedFrame else { return }
        guard let pixelSize = updateBackgroundPixelSize() else { return }
        let style = canvasBackgroundStyle
        let loop = CanvasAppearance.animationLoopDuration
        let phase = ((CACurrentMediaTime() - backgroundAnimationStart) / loop).truncatingRemainder(dividingBy: 1)
        isRenderingAnimatedFrame = true
        backgroundAnimationQueue.async { [weak self] in
            let image = style.appearance.renderCGImage(pixelWidth: pixelSize.width, pixelHeight: pixelSize.height, animationPhase: phase)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRenderingAnimatedFrame = false
                guard self.canvasBackgroundAnimated,
                      self.canvasBackgroundStyle == style,
                      self.canvasBackgroundStyle.supportsBackgroundAnimation else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.canvasBackgroundLayer.contents = image
                CATransaction.commit()
            }
        }
    }

    func updateCanvasSelectionAffordance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isBackgroundLayerSelected {
            canvasBackgroundLayer.borderColor = Self.backgroundSelectionColor.cgColor
            canvasBackgroundLayer.borderWidth = 2
        } else {
            canvasBackgroundLayer.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
            canvasBackgroundLayer.borderWidth = 1.5
        }
        CATransaction.commit()
    }

    private static let backgroundSelectionColor = NSColor(srgbRed: 0.09, green: 1.0, blue: 0.65, alpha: 0.95)
}
