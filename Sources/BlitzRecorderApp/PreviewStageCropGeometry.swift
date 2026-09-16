import CoreGraphics

enum PreviewStageCropGeometry {
    static func fittedSourceFrame(target: CGRect, sourceAspectRatio: CGFloat) -> CGRect {
        guard sourceAspectRatio > 0, target.width > 0, target.height > 0 else { return target }
        let targetAspect = target.width / target.height
        if targetAspect > sourceAspectRatio {
            let height = target.width / sourceAspectRatio
            return CGRect(x: target.minX, y: target.midY - height / 2, width: target.width, height: height)
        }
        let width = target.height * sourceAspectRatio
        return CGRect(x: target.midX - width / 2, y: target.minY, width: width, height: target.height)
    }

    static func cropFrame(in sourceFrame: CGRect, normalizedCrop: CGRect) -> CGRect {
        let crop = clampedNormalized(normalizedCrop)
        return CGRect(
            x: sourceFrame.minX + crop.minX * sourceFrame.width,
            y: sourceFrame.minY + (1 - crop.maxY) * sourceFrame.height,
            width: crop.width * sourceFrame.width,
            height: crop.height * sourceFrame.height
        )
    }

    static func normalizedCrop(pixelFrame: CGRect, in sourceFrame: CGRect) -> CGRect {
        guard sourceFrame.width > 0, sourceFrame.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return clampedNormalized(CGRect(
            x: (pixelFrame.minX - sourceFrame.minX) / sourceFrame.width,
            y: 1 - ((pixelFrame.maxY - sourceFrame.minY) / sourceFrame.height),
            width: pixelFrame.width / sourceFrame.width,
            height: pixelFrame.height / sourceFrame.height
        ))
    }

    static func defaultDraft(sourceFrame: CGRect, targetFrame: CGRect) -> CGRect {
        guard sourceFrame.width > 0, sourceFrame.height > 0, !targetFrame.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let visibleTarget = targetFrame.intersection(sourceFrame)
        guard !visibleTarget.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return normalizedCrop(pixelFrame: visibleTarget, in: sourceFrame)
    }

    static func clampedNormalized(_ crop: CGRect) -> CGRect {
        let crop = crop.standardized
        let x = min(1, max(0, crop.minX))
        let y = min(1, max(0, crop.minY))
        let maxX = min(1, max(x, crop.maxX))
        let maxY = min(1, max(y, crop.maxY))
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    static func clampedPixelFrame(_ frame: CGRect, in sourceFrame: CGRect) -> CGRect {
        let minimumWidth = min(sourceFrame.width, max(12, sourceFrame.width * 0.05))
        let minimumHeight = min(sourceFrame.height, max(12, sourceFrame.height * 0.05))
        let width = min(sourceFrame.width, max(minimumWidth, frame.width))
        let height = min(sourceFrame.height, max(minimumHeight, frame.height))
        let x = min(sourceFrame.maxX - width, max(sourceFrame.minX, frame.minX))
        let y = min(sourceFrame.maxY - height, max(sourceFrame.minY, frame.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func resizedPixelFrame(
        _ frame: CGRect,
        delta: CGPoint,
        anchor: ResizeAnchor,
        in sourceFrame: CGRect
    ) -> CGRect {
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY
        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }
        return clampedPixelFrame(
            CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            in: sourceFrame
        )
    }

    static func dragDelta(from startPoint: CGPoint, to location: CGPoint) -> CGPoint {
        CGPoint(x: location.x - startPoint.x, y: location.y - startPoint.y)
    }
}

enum PreviewStageCropSession {
    static func committedCameraCrop(
        isEditing: Bool,
        amount: CGPoint,
        position: CGPoint
    ) -> (CGPoint, CGPoint)? {
        guard isEditing else { return nil }
        return (amount, position)
    }

    static func committedScreenCrop(isEditing: Bool, draft: CGRect?) -> CGRect? {
        guard isEditing else { return nil }
        return PreviewStageCropGeometry.clampedNormalized(draft ?? CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
