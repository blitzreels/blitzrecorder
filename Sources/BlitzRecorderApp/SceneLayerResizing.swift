import CoreGraphics

enum ResizeAnchor {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case right
    case bottom
    case left
}

enum SceneLayerResizing {
    static let minimumSize: CGFloat = 0.08
    static let maximumSize: CGFloat = 4

    static func resized(_ frame: CGRect, delta: CGPoint, anchor: ResizeAnchor, aspectRatio: CGFloat? = nil) -> CGRect {
        if let aspectRatio, aspectRatio > 0 {
            return aspectLockedResized(frame, delta: delta, anchor: anchor, aspectRatio: aspectRatio)
        }

        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY

        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }

        if maxX - minX < minimumSize {
            if anchor.resizesLeftEdge {
                minX = maxX - minimumSize
            } else {
                maxX = minX + minimumSize
            }
        }
        if maxY - minY < minimumSize {
            if anchor.resizesBottomEdge {
                minY = maxY - minimumSize
            } else {
                maxY = minY + minimumSize
            }
        }

        return clamped(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private static func aspectLockedResized(
        _ frame: CGRect,
        delta: CGPoint,
        anchor: ResizeAnchor,
        aspectRatio: CGFloat
    ) -> CGRect {
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY

        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }

        let proposedSize = CGSize(width: max(0.01, maxX - minX), height: max(0.01, maxY - minY))
        let currentSize = CGSize(width: max(0.01, frame.width), height: max(0.01, frame.height))
        let widthScale = proposedSize.width / currentSize.width
        let heightScale = proposedSize.height / currentSize.height
        let scale: CGFloat

        if anchor.resizesHorizontalEdgeOnly {
            scale = widthScale
        } else if anchor.resizesVerticalEdgeOnly {
            scale = heightScale
        } else {
            let widthDeviation = abs(widthScale - 1)
            let heightDeviation = abs(heightScale - 1)
            scale = widthDeviation >= heightDeviation ? widthScale : heightScale
        }

        return aspectLockedFrame(from: frame, scale: scale, aspectRatio: aspectRatio, anchor: anchor)
    }

    private static func aspectLockedFrame(
        from frame: CGRect,
        scale: CGFloat,
        aspectRatio: CGFloat,
        anchor: ResizeAnchor
    ) -> CGRect {
        let minimumHeight = minimumSize
        let minimumWidth = minimumHeight * aspectRatio
        var width = max(minimumWidth, frame.width * scale)
        var height = width / aspectRatio
        if height < minimumHeight {
            height = minimumHeight
            width = height * aspectRatio
        }
        if width > maximumSize {
            width = maximumSize
            height = width / aspectRatio
        }
        if height > maximumSize {
            height = maximumSize
            width = height * aspectRatio
        }

        let x: CGFloat
        if anchor.resizesLeftEdge {
            x = frame.maxX - width
        } else if anchor.resizesRightEdge {
            x = frame.minX
        } else {
            x = frame.midX - width / 2
        }

        let y: CGFloat
        if anchor.resizesBottomEdge {
            y = frame.maxY - height
        } else if anchor.resizesTopEdge {
            y = frame.minY
        } else {
            y = frame.midY - height / 2
        }

        return clamped(CGRect(x: x, y: y, width: width, height: height))
    }

    static func clamped(_ frame: CGRect) -> CGRect {
        let width = min(maximumSize, max(minimumSize, frame.width))
        let height = min(maximumSize, max(minimumSize, frame.height))
        let x = min(max(0, 1 - width), max(min(0, 1 - width), frame.minX))
        let y = min(max(0, 1 - height), max(min(0, 1 - height), frame.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension ResizeAnchor {
    var resizesLeftEdge: Bool {
        self == .topLeft || self == .bottomLeft || self == .left
    }

    var resizesRightEdge: Bool {
        self == .topRight || self == .bottomRight || self == .right
    }

    var resizesBottomEdge: Bool {
        self == .bottomLeft || self == .bottomRight || self == .bottom
    }

    var resizesTopEdge: Bool {
        self == .topLeft || self == .topRight || self == .top
    }

    var resizesHorizontalEdgeOnly: Bool {
        self == .left || self == .right
    }

    var resizesVerticalEdgeOnly: Bool {
        self == .top || self == .bottom
    }
}
