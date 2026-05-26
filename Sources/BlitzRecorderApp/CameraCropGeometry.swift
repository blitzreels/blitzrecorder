import CoreGraphics

struct CameraCropControl: Equatable {
    let amount: CGPoint
    let position: CGPoint
}

struct CameraCropGeometry {
    let renderGeometry: SceneRenderGeometry
    let sourceAspectRatio: CGFloat
    let minimumCropScale: CGFloat

    init(
        renderGeometry: SceneRenderGeometry,
        sourceAspectRatio: CGFloat,
        minimumCropScale: CGFloat = 0.25
    ) {
        self.renderGeometry = renderGeometry
        self.sourceAspectRatio = sourceAspectRatio
        self.minimumCropScale = minimumCropScale
    }

    var sourceFrame: CGRect {
        renderGeometry.cameraCropSourceFrame(sourceAspectRatio: sourceAspectRatio)
    }

    var targetFrame: CGRect {
        renderGeometry.targetRect(for: .camera)
    }

    var baseCropFrame: CGRect {
        renderGeometry.baseCameraCropFrame(sourceAspectRatio: sourceAspectRatio)
    }

    var cropAspectRatio: CGFloat {
        guard targetFrame.width > 0, targetFrame.height > 0 else { return 1 }
        return targetFrame.width / targetFrame.height
    }

    func cropFrame(amount: CGPoint, position: CGPoint) -> CGRect {
        renderGeometry.cameraCropFrame(
            sourceAspectRatio: sourceAspectRatio,
            sourceCropAmount: amount,
            sourceCropPosition: position
        )
    }

    func movedCropFrame(_ crop: CGRect, delta: CGPoint) -> CGRect {
        clampedCropFrame(CGRect(
            x: crop.minX + delta.x,
            y: crop.minY + delta.y,
            width: crop.width,
            height: crop.height
        ))
    }

    func resizedCropFrame(_ crop: CGRect, delta: CGPoint, anchor: ResizeAnchor) -> CGRect {
        var minX = crop.minX
        var maxX = crop.maxX
        var minY = crop.minY
        var maxY = crop.maxY

        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }

        let currentWidth = max(0.0001, crop.width)
        let currentHeight = max(0.0001, crop.height)
        let widthScale = max(0.0001, maxX - minX) / currentWidth
        let heightScale = max(0.0001, maxY - minY) / currentHeight
        let scale: CGFloat
        if anchor.resizesHorizontalEdgeOnly {
            scale = widthScale
        } else if anchor.resizesVerticalEdgeOnly {
            scale = heightScale
        } else {
            scale = abs(widthScale - 1) >= abs(heightScale - 1) ? widthScale : heightScale
        }

        let maximumCrop = baseCropFrame
        let minWidth = maximumCrop.width * minimumCropScale
        let minHeight = maximumCrop.height * minimumCropScale
        var width = min(maximumCrop.width, max(minWidth, crop.width * scale))
        var height = width / cropAspectRatio
        if height > maximumCrop.height {
            height = maximumCrop.height
            width = height * cropAspectRatio
        }
        if height < minHeight {
            height = minHeight
            width = height * cropAspectRatio
        }

        let x: CGFloat
        if anchor.resizesLeftEdge {
            x = crop.maxX - width
        } else if anchor.resizesRightEdge {
            x = crop.minX
        } else {
            x = crop.midX - width / 2
        }

        let y: CGFloat
        if anchor.resizesBottomEdge {
            y = crop.maxY - height
        } else if anchor.resizesTopEdge {
            y = crop.minY
        } else {
            y = crop.midY - height / 2
        }

        return clampedCropFrame(CGRect(x: x, y: y, width: width, height: height))
    }

    func control(for crop: CGRect) -> CameraCropControl? {
        let baseCrop = baseCropFrame
        guard baseCrop.width > 0, baseCrop.height > 0 else { return nil }
        let scale = min(
            crop.width / max(1, baseCrop.width),
            crop.height / max(1, baseCrop.height)
        )
        return CameraCropControl(
            amount: CGPoint(
                x: SourceCropGeometry.clampedCropAmount(1 - scale),
                y: SourceCropGeometry.clampedCropAmount(1 - scale)
            ),
            position: CGPoint(
                x: SourceCropGeometry.clampedCropPosition((crop.midX - sourceFrame.midX) / max(0.0001, (sourceFrame.width - crop.width) / 2)),
                y: SourceCropGeometry.clampedCropPosition((crop.midY - sourceFrame.midY) / max(0.0001, (sourceFrame.height - crop.height) / 2))
            )
        )
    }

    func clampedCropFrame(_ crop: CGRect) -> CGRect {
        let baseCrop = baseCropFrame
        let width = min(baseCrop.width, max(1, crop.width))
        let height = min(baseCrop.height, max(1, crop.height))
        return CGRect(
            x: min(max(sourceFrame.minX, crop.minX), sourceFrame.maxX - width),
            y: min(max(sourceFrame.minY, crop.minY), sourceFrame.maxY - height),
            width: width,
            height: height
        )
    }
}
