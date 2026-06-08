import CoreGraphics
import CoreImage
import CoreVideo
import Metal

final class LiveCompositorRenderer: @unchecked Sendable {
    /// Animated-background frames per loop. 8s loop ÷ 96 ≈ 12 fps of background
    /// motion, which the per-frame cache collapses so we render ~12×/s, not 60×/s.
    private static let backgroundFramesPerLoop = 96

    private let ciContext: CIContext
    private var cachedBackground: (style: CanvasBackgroundStyle, size: CGSize, frameIndex: Int, image: CIImage)?

    init(metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        if let metalDevice {
            ciContext = CIContext(mtlDevice: metalDevice, options: [.cacheIntermediates: false])
        } else {
            ciContext = CIContext(options: [.cacheIntermediates: false])
        }
    }

    func render(
        screenBuffer: CVPixelBuffer?,
        cameraBuffer: CVPixelBuffer?,
        scene: RecordingScene,
        settings: RecordingSettings,
        backgroundPhase: Double? = nil,
        to outputBuffer: CVPixelBuffer
    ) -> Bool {
        guard screenBuffer != nil || cameraBuffer != nil else {
            return false
        }

        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let canvasRect = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        let geometry = SceneRenderGeometry(canvas: canvasRect, scene: scene, origin: .lowerLeft)
        var image = backgroundImage(
            style: scene.canvasBackgroundStyle,
            animationPhase: scene.canvasBackgroundAnimated && scene.canvasBackgroundStyle.supportsBackgroundAnimation ? backgroundPhase : nil,
            in: canvasRect
        )

        for placement in geometry.activePlacements {
            let opacity = scene.sourceOpacity(for: placement.kind.source)
            guard opacity > 0.001 else { continue }
            switch placement.kind {
            case .screen:
                guard let screenBuffer else { continue }
                image = fill(
                    CIImage(cvPixelBuffer: screenBuffer),
                    into: placement.targetRect,
                    cornerRadius: placement.cornerRadius
                )
                .settingOpacity(opacity)
                .composited(over: image)
            case .camera:
                guard let cameraBuffer else { continue }
                image = fill(
                    CIImage(cvPixelBuffer: cameraBuffer),
                    into: placement.targetRect,
                    sourceCrop: { placement.videoPlacement.sourceCropRectangle(sourceExtent: $0) },
                    cornerRadius: placement.cornerRadius
                )
                .settingOpacity(opacity)
                .composited(over: image)
            }
        }

        ciContext.render(image, to: outputBuffer, bounds: canvasRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return true
    }

    func reset() {
        cachedBackground = nil
    }

    private func backgroundImage(style: CanvasBackgroundStyle, animationPhase: Double?, in canvasRect: CGRect) -> CIImage {
        let frameIndex: Int
        if let phase = animationPhase {
            let wrapped = (phase.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            frameIndex = min(Self.backgroundFramesPerLoop - 1, Int(wrapped * Double(Self.backgroundFramesPerLoop)))
        } else {
            frameIndex = -1
        }

        if let cachedBackground,
           cachedBackground.style == style,
           cachedBackground.size == canvasRect.size,
           cachedBackground.frameIndex == frameIndex {
            return cachedBackground.image
        }

        let image: CIImage
        if frameIndex < 0 {
            image = style.appearance.ciImage(in: canvasRect)
        } else {
            image = Self.animatedBackgroundImage(
                style: style,
                frameIndex: frameIndex,
                framesPerLoop: Self.backgroundFramesPerLoop,
                canvasRect: canvasRect
            )
        }
        cachedBackground = (style, canvasRect.size, frameIndex, image)
        return image
    }

    /// Animated background frame, rendered at a capped resolution then scaled to
    /// the canvas (the mesh is soft, so upscaling is invisible and keeps the
    /// per-frame render cheap even at 4K).
    private static func animatedBackgroundImage(
        style: CanvasBackgroundStyle,
        frameIndex: Int,
        framesPerLoop: Int,
        canvasRect: CGRect
    ) -> CIImage {
        let cap: CGFloat = 1280
        let longEdge = max(canvasRect.width, canvasRect.height)
        let scale = longEdge > cap ? cap / longEdge : 1
        let width = max(1, Int((canvasRect.width * scale).rounded(.up)))
        let height = max(1, Int((canvasRect.height * scale).rounded(.up)))
        let phase = Double(frameIndex) / Double(framesPerLoop)
        guard let cgImage = style.appearance.renderCGImage(pixelWidth: width, pixelHeight: height, animationPhase: phase) else {
            return CIImage(color: CIColor(cgColor: style.appearance.solidCGColor)).cropped(to: canvasRect)
        }
        return CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: canvasRect.width / CGFloat(width), y: canvasRect.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: canvasRect.minX, y: canvasRect.minY))
            .cropped(to: canvasRect)
    }

    private func fill(
        _ image: CIImage,
        into target: CGRect,
        sourceCrop: ((CGRect) -> CGRect),
        cornerRadius: CGFloat = 0
    ) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let croppedImage = image.cropped(to: sourceCrop(source))
        return fill(croppedImage, into: target, cornerRadius: cornerRadius)
    }

    private func fill(_ image: CIImage, into target: CGRect, cornerRadius: CGFloat = 0) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let scale = max(target.width / source.width, target.height / source.height)
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let x = target.midX - scaledWidth / 2
        let y = target.midY - scaledHeight / 2
        return image
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: x, y: y))
            .cropped(to: target)
            .rounded(to: target, radius: cornerRadius)
    }

}

private extension CIImage {
    func settingOpacity(_ opacity: CGFloat) -> CIImage {
        let opacity = min(1, max(0, opacity))
        guard opacity < 0.999 else { return self }
        return applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
            ]
        )
    }

    func rounded(to rect: CGRect, radius: CGFloat) -> CIImage {
        guard radius > 0,
              let filter = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return self
        }
        filter.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(CIColor.white, forKey: "inputColor")
        guard let mask = filter.outputImage?.cropped(to: rect) else {
            return self
        }
        return applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask
            ]
        )
        .cropped(to: rect)
    }
}
