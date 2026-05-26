import CoreGraphics
import CoreImage
import CoreVideo
import Metal

final class LiveCompositorRenderer: @unchecked Sendable {
    private let ciContext: CIContext
    private var cachedBackground: (style: CanvasBackgroundStyle, size: CGSize, image: CIImage)?

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
        to outputBuffer: CVPixelBuffer
    ) -> Bool {
        guard screenBuffer != nil || cameraBuffer != nil else {
            return false
        }

        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let canvasRect = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        let geometry = SceneRenderGeometry(canvas: canvasRect, scene: scene, origin: .lowerLeft)
        var image = backgroundImage(style: scene.canvasBackgroundStyle, in: canvasRect)

        for layer in geometry.activeLayerOrder {
            switch layer {
            case .screen:
                guard let screenBuffer else { continue }
                let rect = geometry.targetRect(for: .screen)
                image = fill(
                    CIImage(cvPixelBuffer: screenBuffer),
                    into: rect,
                    cornerRadius: geometry.sourceCornerRadius(for: .screen)
                )
                .composited(over: image)
            case .camera:
                guard let cameraBuffer else { continue }
                let rect = geometry.targetRect(for: .camera)
                image = fill(
                    CIImage(cvPixelBuffer: cameraBuffer),
                    into: rect,
                    sourceCrop: { geometry.sourceCropRectangle(for: .camera, sourceExtent: $0) },
                    cornerRadius: geometry.sourceCornerRadius(for: .camera)
                )
                .composited(over: image)
            }
        }

        ciContext.render(image, to: outputBuffer, bounds: canvasRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return true
    }

    func reset() {
        cachedBackground = nil
    }

    private func backgroundImage(style: CanvasBackgroundStyle, in canvasRect: CGRect) -> CIImage {
        if let cachedBackground,
           cachedBackground.style == style,
           cachedBackground.size == canvasRect.size {
            return cachedBackground.image
        }

        let image = style.appearance.ciImage(in: canvasRect)
        cachedBackground = (style, canvasRect.size, image)
        return image
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
