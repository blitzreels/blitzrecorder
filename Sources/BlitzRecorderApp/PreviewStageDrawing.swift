import AppKit
import CoreGraphics
import QuartzCore

enum PreviewStageDrawing {
    static func maskPath(for rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = min(radius, SceneLayoutProjection.circularCornerRadius(for: rect))
        guard radius > 0 else {
            return CGPath(rect: rect, transform: nil)
        }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    struct SourceShapeRequest: Equatable {
        let isCamera: Bool
        let rect: CGRect
        let isFullscreen: Bool
        let isFullWidth: Bool
        let isCircle: Bool
    }

    static func maskCornerRadius(_ request: SourceShapeRequest) -> CGFloat {
        request.isCamera ? PreviewStageLayout.cameraPreviewCornerRadius(request) : 0
    }

    struct SourceShape: Equatable {
        var cornerRadius: CGFloat
        var borderWidth: CGFloat
        var borderAlpha: CGFloat
        var isCircle: Bool
    }

    static func sourceShape(_ request: SourceShapeRequest) -> SourceShape {
        if request.isCamera {
            let radius = PreviewStageLayout.cameraPreviewCornerRadius(request)
            return SourceShape(
                cornerRadius: radius,
                borderWidth: radius > 0 ? 1 : 0,
                borderAlpha: 0.16,
                isCircle: request.isCircle
            )
        }
        let radius = SceneLayoutProjection.sourceCornerRadius(for: request.rect, normalizedRadius: 0)
        return SourceShape(cornerRadius: radius, borderWidth: radius > 0 ? 1 : 0, borderAlpha: 0.14, isCircle: false)
    }

    static func apply(_ shape: SourceShape, to layer: CALayer) {
        layer.cornerRadius = shape.cornerRadius
        layer.cornerCurve = shape.isCircle ? .circular : .continuous
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
