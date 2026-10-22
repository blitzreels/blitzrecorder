import CoreGraphics

enum ResizeAnchor: Equatable {
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
    struct AspectRatioChange {
        let frame: CGRect
        let aspectRatio: CGFloat
    }

    static let minimumSize: CGFloat = 0.08
    static let maximumSize: CGFloat = 4

    static func settingAspectRatio(_ change: AspectRatioChange) -> CGRect {
        guard change.aspectRatio > 0, change.frame.width > 0, change.frame.height > 0 else {
            return clamped(change.frame)
        }

        let area = change.frame.width * change.frame.height
        var width = sqrt(area * change.aspectRatio)
        var height = width / change.aspectRatio

        if width < minimumSize {
            width = minimumSize
            height = width / change.aspectRatio
        }
        if height < minimumSize {
            height = minimumSize
            width = height * change.aspectRatio
        }
        if width > maximumSize {
            width = maximumSize
            height = width / change.aspectRatio
        }
        if height > maximumSize {
            height = maximumSize
            width = height * change.aspectRatio
        }

        return clamped(CGRect(
            x: change.frame.midX - width / 2,
            y: change.frame.midY - height / 2,
            width: width,
            height: height
        ))
    }

    static func resized(_ frame: CGRect, delta: CGPoint, anchor: ResizeAnchor, aspectRatio: CGFloat? = nil) -> CGRect {
        if let aspectRatio, aspectRatio > 0 {
            return aspectLockedResized(frame, delta: delta, anchor: anchor, aspectRatio: aspectRatio)
        }

        var edges = ResizeDrag(frame: frame, delta: delta, anchor: anchor).movedEdges

        if edges.maxX - edges.minX < minimumSize {
            if anchor.resizesLeftEdge {
                edges.minX = edges.maxX - minimumSize
            } else {
                edges.maxX = edges.minX + minimumSize
            }
        }
        if edges.maxY - edges.minY < minimumSize {
            if anchor.resizesBottomEdge {
                edges.minY = edges.maxY - minimumSize
            } else {
                edges.maxY = edges.minY + minimumSize
            }
        }

        return clamped(edges.rect)
    }

    private static func aspectLockedResized(
        _ frame: CGRect,
        delta: CGPoint,
        anchor: ResizeAnchor,
        aspectRatio: CGFloat
    ) -> CGRect {
        let edges = ResizeDrag(frame: frame, delta: delta, anchor: anchor).movedEdges
        let proposedSize = CGSize(width: max(0.01, edges.maxX - edges.minX), height: max(0.01, edges.maxY - edges.minY))
        let currentSize = CGSize(width: max(0.01, frame.width), height: max(0.01, frame.height))
        let widthScale = proposedSize.width / currentSize.width
        let heightScale = proposedSize.height / currentSize.height
        let scale: CGFloat

        if anchor.keepsAspectRatio {
            let horizontalDirection: CGFloat = anchor.resizesLeftEdge ? -1 : 1
            let verticalDirection: CGFloat = anchor.resizesBottomEdge ? -1 : 1
            let originalX = currentSize.width * horizontalDirection
            let originalY = currentSize.height * verticalDirection
            let movedX = originalX + delta.x
            let movedY = originalY + delta.y
            let magnitudeSquared = originalX * originalX + originalY * originalY
            scale = magnitudeSquared > 0
                ? (movedX * originalX + movedY * originalY) / magnitudeSquared
                : 1
        } else if anchor.resizesHorizontalEdgeOnly {
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

    static func scaled(_ frame: CGRect, aroundCenterBy ratio: CGFloat) -> CGRect {
        guard ratio.isFinite, ratio > 0 else { return clamped(frame) }
        return clamped(CGRect(
            x: frame.midX - (frame.width * ratio) / 2,
            y: frame.midY - (frame.height * ratio) / 2,
            width: frame.width * ratio,
            height: frame.height * ratio
        ))
    }

    static func clamped(_ frame: CGRect) -> CGRect {
        let width = min(maximumSize, max(minimumSize, frame.width))
        let height = min(maximumSize, max(minimumSize, frame.height))
        let x = min(max(0, 1 - width), max(min(0, 1 - width), frame.minX))
        let y = min(max(0, 1 - height), max(min(0, 1 - height), frame.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct ResizeEdges {
    var minX: CGFloat
    var maxX: CGFloat
    var minY: CGFloat
    var maxY: CGFloat

    var rect: CGRect {
        CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct ResizeDrag {
    let frame: CGRect
    let delta: CGPoint
    let anchor: ResizeAnchor

    var movedEdges: ResizeEdges {
        var edges = ResizeEdges(minX: frame.minX, maxX: frame.maxX, minY: frame.minY, maxY: frame.maxY)
        if anchor.resizesLeftEdge { edges.minX += delta.x }
        if anchor.resizesRightEdge { edges.maxX += delta.x }
        if anchor.resizesBottomEdge { edges.minY += delta.y }
        if anchor.resizesTopEdge { edges.maxY += delta.y }
        return edges
    }
}

extension ResizeAnchor {
    var keepsAspectRatio: Bool {
        !resizesHorizontalEdgeOnly && !resizesVerticalEdgeOnly
    }

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
