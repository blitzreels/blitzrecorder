import AppKit
import CoreGraphics
import QuartzCore

enum PreviewStageDrawing {
    static func maskPath(for rect: CGRect, radius: CGFloat) -> CGPath {
        guard radius > 0 else {
            return CGPath(rect: rect, transform: nil)
        }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func maskCornerRadius(
        visibleRect: CGRect,
        isCamera: Bool,
        isFullscreen: Bool,
        isFullWidth: Bool
    ) -> CGFloat {
        let paddedRadius = SceneLayoutProjection.sourceCornerRadius(for: visibleRect, normalizedRadius: 0)
        guard paddedRadius <= 0, isCamera, !isFullscreen, !isFullWidth else {
            return paddedRadius
        }
        return PreviewStageLayout.sourceCornerRadius(for: visibleRect)
    }

    struct SourceShape: Equatable {
        var cornerRadius: CGFloat
        var borderWidth: CGFloat
        var borderAlpha: CGFloat
    }

    static func sourceShape(
        isCamera: Bool,
        bounds: CGRect,
        isFullscreen: Bool,
        isFullWidth: Bool
    ) -> SourceShape {
        if isCamera {
            let radius = PreviewStageLayout.cameraPreviewCornerRadius(
                bounds: bounds,
                isFullscreen: isFullscreen,
                isFullWidth: isFullWidth
            )
            return SourceShape(cornerRadius: radius, borderWidth: radius > 0 ? 1 : 0, borderAlpha: 0.16)
        }
        let radius = SceneLayoutProjection.sourceCornerRadius(for: bounds, normalizedRadius: 0)
        return SourceShape(cornerRadius: radius, borderWidth: radius > 0 ? 1 : 0, borderAlpha: 0.14)
    }

    static func apply(_ shape: SourceShape, to layer: CALayer) {
        layer.cornerRadius = shape.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = shape.borderWidth
        layer.borderColor = NSColor.white.withAlphaComponent(shape.borderAlpha).cgColor
    }

    static func canvasRectInView(canvasFrame: CGRect, viewFrame: CGRect) -> CGRect {
        CGRect(
            x: canvasFrame.minX - viewFrame.minX,
            y: canvasFrame.minY - viewFrame.minY,
            width: canvasFrame.width,
            height: canvasFrame.height
        )
    }
}
