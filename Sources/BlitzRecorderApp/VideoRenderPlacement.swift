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

    var contentMode: VideoRenderContentMode {
        switch kind {
        case .screen:
            return .aspectFill
        case .camera:
            return .aspectFill
        }
    }

    func transform(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGAffineTransform {
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = VideoRenderPlacement.orientedSize(size: naturalSize, transform: preferredTransform)
        let cropRect = cropRectangle(naturalSize: orientedSize)
        let scale = cropRect.map { min(targetRect.width / $0.width, targetRect.height / $0.height) }
            ?? scale(for: orientedSize)
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let x = cropRect.map { targetRect.minX - $0.minX * scale }
            ?? (targetRect.midX - scaledSize.width / 2)
        let y = cropRect.map { targetRect.minY - $0.minY * scale }
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
