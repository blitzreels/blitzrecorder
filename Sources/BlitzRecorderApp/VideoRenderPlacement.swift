import CoreGraphics

enum VideoRenderContentMode {
    case aspectFit
    case aspectFill
}

struct VideoRenderPlacement {
    let kind: SceneLayerKind
    let targetRect: CGRect
    var sourceCropAmount: CGPoint = .zero
    var sourceCropPosition: CGPoint = .zero
    var contentMode: VideoRenderContentMode = .aspectFill

    func transform(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGAffineTransform {
        transform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            cropRectangle: nil
        )
    }

    func transform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        cropRectangle: CGRect?
    ) -> CGAffineTransform {
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = VideoRenderPlacement.orientedSize(size: naturalSize, transform: preferredTransform)
        let cropRect = cropRectangle ?? self.cropRectangle(naturalSize: orientedSize)
        let scale = cropRect.map { max(targetRect.width / $0.width, targetRect.height / $0.height) }
            ?? scale(for: orientedSize)
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let x = cropRect.map { targetRect.midX - $0.midX * scale }
            ?? (targetRect.midX - scaledSize.width / 2)
        let y = cropRect.map { targetRect.midY - $0.midY * scale }
            ?? (targetRect.midY - scaledSize.height / 2)

        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }

    func cropRectangle(naturalSize: CGSize) -> CGRect? {
        guard contentMode == .aspectFill,
              naturalSize.width > 0,
              naturalSize.height > 0,
              targetRect.width > 0,
              targetRect.height > 0 else {
            return nil
        }

        return SourceCropGeometry.cropRectangle(
            source: CGRect(origin: .zero, size: naturalSize),
            target: targetRect,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
    }

    func sourceFrame(sourceAspectRatio: CGFloat) -> CGRect {
        if contentMode == .aspectFit {
            return aspectFitSourceFrame(sourceAspectRatio: sourceAspectRatio)
        }
        return SourceCropGeometry.sourceFrame(
            sourceAspectRatio: sourceAspectRatio,
            bounds: targetRect,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
    }

    func sourceCropRectangle(sourceExtent: CGRect) -> CGRect {
        SourceCropGeometry.cropRectangle(
            source: sourceExtent,
            target: targetRect,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
    }

    func pixelAlignedCropRectangle(naturalSize: CGSize) -> CGRect? {
        guard let cropRectangle = cropRectangle(naturalSize: naturalSize) else {
            return nil
        }
        return VideoRenderPlacement.pixelAligned(cropRectangle, within: CGRect(origin: .zero, size: naturalSize))
    }

    func pixelAlignedOrientedCropRectangle(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGRect? {
        let orientedSize = VideoRenderPlacement.orientedSize(size: naturalSize, transform: preferredTransform)
        guard let cropRectangle = cropRectangle(naturalSize: orientedSize) else {
            return nil
        }
        return VideoRenderPlacement.pixelAligned(cropRectangle, within: CGRect(origin: .zero, size: orientedSize))
    }

    func pixelAlignedSourceCropRectangle(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGRect? {
        guard let orientedCrop = pixelAlignedOrientedCropRectangle(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        ) else {
            return nil
        }

        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientationTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY)
        )
        let sourceCrop = orientedCrop.applying(orientationTransform.inverted())
        return VideoRenderPlacement.pixelAligned(
            sourceCrop,
            within: CGRect(origin: .zero, size: naturalSize)
        )
    }

    private static func pixelAligned(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        let alignment: CGFloat = 2
        let minX = max(bounds.minX, floor(rect.minX / alignment) * alignment)
        let minY = max(bounds.minY, floor(rect.minY / alignment) * alignment)
        let maxX = min(bounds.maxX, ceil(rect.maxX / alignment) * alignment)
        let maxY = min(bounds.maxY, ceil(rect.maxY / alignment) * alignment)
        guard maxX > minX, maxY > minY else {
            return bounds
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func scale(for orientedSize: CGSize) -> CGFloat {
        switch contentMode {
        case .aspectFit:
            return min(targetRect.width / orientedSize.width, targetRect.height / orientedSize.height)
        case .aspectFill:
            return max(targetRect.width / orientedSize.width, targetRect.height / orientedSize.height)
        }
    }

    private static func orientedSize(size: CGSize, transform: CGAffineTransform) -> CGSize {
        let transformed = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private func aspectFitSourceFrame(sourceAspectRatio: CGFloat) -> CGRect {
        guard sourceAspectRatio > 0,
              targetRect.width > 0,
              targetRect.height > 0 else {
            return targetRect
        }
        let targetAspectRatio = targetRect.width / targetRect.height
        if targetAspectRatio > sourceAspectRatio {
            let width = targetRect.height * sourceAspectRatio
            return CGRect(x: targetRect.midX - width / 2, y: targetRect.minY, width: width, height: targetRect.height)
        }
        let height = targetRect.width / sourceAspectRatio
        return CGRect(x: targetRect.minX, y: targetRect.midY - height / 2, width: targetRect.width, height: height)
    }
}

enum SourceCropGeometry {
    static func sourceFrame(
        sourceAspectRatio: CGFloat,
        bounds: CGRect,
        sourceCropAmount: CGPoint,
        sourceCropPosition: CGPoint
    ) -> CGRect {
        guard sourceAspectRatio > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let source = CGRect(x: 0, y: 0, width: sourceAspectRatio, height: 1)
        let cropRect = cropRectangle(
            source: source,
            target: bounds,
            sourceCropAmount: sourceCropAmount,
            sourceCropPosition: sourceCropPosition
        )
        let scale = min(bounds.width / cropRect.width, bounds.height / cropRect.height)
        return CGRect(
            x: bounds.minX - cropRect.minX * scale,
            y: bounds.minY - cropRect.minY * scale,
            width: source.width * scale,
            height: source.height * scale
        )
    }

    static func cropRectangle(
        source: CGRect,
        target: CGRect,
        sourceCropAmount: CGPoint,
        sourceCropPosition: CGPoint
    ) -> CGRect {
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return source
        }

        let sourceAspectRatio = source.width / source.height
        let targetAspectRatio = target.width / target.height
        let baseWidth: CGFloat
        let baseHeight: CGFloat
        if sourceAspectRatio > targetAspectRatio {
            baseWidth = source.height * targetAspectRatio
            baseHeight = source.height
        } else {
            baseWidth = source.width
            baseHeight = source.width / targetAspectRatio
        }

        let requestedWidth = baseWidth * (1 - clampedCropAmount(sourceCropAmount.x))
        let requestedHeight = baseHeight * (1 - clampedCropAmount(sourceCropAmount.y))
        let width = min(requestedWidth, requestedHeight * targetAspectRatio)
        let height = width / targetAspectRatio
        let maxOffsetX = (source.width - width) / 2
        let maxOffsetY = (source.height - height) / 2
        return CGRect(
            x: source.minX + maxOffsetX + clampedCropPosition(sourceCropPosition.x) * maxOffsetX,
            y: source.minY + maxOffsetY + clampedCropPosition(sourceCropPosition.y) * maxOffsetY,
            width: width,
            height: height
        )
    }

    static func clampedCropAmount(_ amount: CGFloat) -> CGFloat {
        min(0.75, max(0, amount))
    }

    static func clampedCropPosition(_ position: CGFloat) -> CGFloat {
        min(1, max(-1, position))
    }
}
