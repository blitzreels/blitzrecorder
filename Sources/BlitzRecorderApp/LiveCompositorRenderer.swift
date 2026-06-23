import CoreGraphics
import CoreImage
import CoreVideo
import Metal

final class LiveCompositorRenderer: @unchecked Sendable {
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
                let visibleCameraRect = geometry.visibleSourceRect(
                    for: .camera,
                    sourceAspectRatio: sourceAspectRatio(for: cameraBuffer)
                )
                if scene.cameraShadowEnabled,
                   cameraIsTopRenderedLayer(in: scene),
                   !geometry.isVisibleSourceFullCanvas(
                       for: .camera,
                       sourceAspectRatio: sourceAspectRatio(for: cameraBuffer)
                   ) {
                    image = shadow(
                        for: visibleCameraRect,
                        cornerRadius: placement.cornerRadius
                    )
                    .settingOpacity(opacity)
                    .composited(over: image)
                }
                image = fill(
                    CIImage(cvPixelBuffer: cameraBuffer),
                    into: placement.targetRect,
                    sourceCrop: { placement.videoPlacement.sourceCropRectangle(sourceExtent: $0) },
                    contentMode: placement.videoPlacement.contentMode,
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

    private func sourceAspectRatio(for pixelBuffer: CVPixelBuffer) -> CGFloat {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard width > 0, height > 0 else { return SceneLayout.cameraAspectRatio }
        return width / height
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
        contentMode: VideoRenderContentMode,
        cornerRadius: CGFloat = 0
    ) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let sourceImage = contentMode == .aspectFill ? image.cropped(to: sourceCrop(source)) : image
        return fill(sourceImage, into: target, contentMode: contentMode, cornerRadius: cornerRadius)
    }

    private func fill(_ image: CIImage, into target: CGRect, cornerRadius: CGFloat = 0) -> CIImage {
        fill(image, into: target, contentMode: .aspectFill, cornerRadius: cornerRadius)
    }

    private func fill(
        _ image: CIImage,
        into target: CGRect,
        contentMode: VideoRenderContentMode,
        cornerRadius: CGFloat = 0
    ) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let scale: CGFloat
        switch contentMode {
        case .aspectFit:
            scale = min(target.width / source.width, target.height / source.height)
        case .aspectFill:
            scale = max(target.width / source.width, target.height / source.height)
        }
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

    private func shadow(for target: CGRect, cornerRadius: CGFloat) -> CIImage {
        guard target.width > 0,
              target.height > 0,
              let filter = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: target)
        }
        let spread = max(24, min(target.width, target.height) * 0.2)
        let shadowRect = target.insetBy(dx: -spread, dy: -spread)
        filter.setValue(CIVector(cgRect: target), forKey: "inputExtent")
        filter.setValue(max(0, cornerRadius), forKey: "inputRadius")
        filter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0.36), forKey: "inputColor")
        let blurredShadow = (filter.outputImage ?? CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: target))
            .cropped(to: shadowRect)
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18])
            .transformed(by: CGAffineTransform(translationX: 0, y: -8))
            .cropped(to: shadowRect)
        return shadowOutsideSource(
            blurredShadow,
            target: target,
            shadowRect: shadowRect,
            cornerRadius: cornerRadius
        )
    }

    private func shadowOutsideSource(
        _ shadow: CIImage,
        target: CGRect,
        shadowRect: CGRect,
        cornerRadius: CGFloat
    ) -> CIImage {
        guard let clipFilter = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return shadow
        }
        clipFilter.setValue(CIVector(cgRect: target), forKey: "inputExtent")
        clipFilter.setValue(max(0, cornerRadius), forKey: "inputRadius")
        clipFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor")

        let outsideMask = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: shadowRect)
        let insideMask = (clipFilter.outputImage ?? CIImage(color: .clear)).cropped(to: shadowRect)
        let mask = outsideMask
            .applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: insideMask])
            .cropped(to: shadowRect)
        let transparent = CIImage(color: .clear).cropped(to: shadowRect)
        return shadow.applyingFilter(
            "CIBlendWithAlphaMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: mask
            ]
        )
        .cropped(to: shadowRect)
    }

    private func cameraIsTopRenderedLayer(in scene: RecordingScene) -> Bool {
        scene.sceneLayout.layerOrder.last(where: { layer in
            switch layer {
            case .screen:
                return scene.renderedSources.contains(.screen)
            case .camera:
                return scene.renderedSources.contains(.camera)
            }
        }) == .camera
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
