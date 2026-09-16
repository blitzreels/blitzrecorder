import AppKit

enum PreviewStageCursors {
    static func cursor(for mode: DragMode.Kind) -> NSCursor {
        switch mode {
        case .cropMove, .screenCropMove, .move:
            return .openHand
        case .screenCropResize(let anchor), .cropResize(let anchor), .resize(let anchor):
            return anchor.cursor
        }
    }
}

extension ResizeAnchor {
    var cursor: NSCursor {
        switch self {
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return .stageDiagonalResizeNWSE
        case .topRight, .bottomLeft:
            return .stageDiagonalResizeNESW
        }
    }
}

extension NSCursor {
    static let stageDiagonalResizeNWSE = diagonalResizeCursor(
        start: CGPoint(x: 6, y: 18),
        end: CGPoint(x: 18, y: 6)
    )

    static let stageDiagonalResizeNESW = diagonalResizeCursor(
        start: CGPoint(x: 6, y: 6),
        end: CGPoint(x: 18, y: 18)
    )

    static func diagonalResizeCursor(start: CGPoint, end: CGPoint) -> NSCursor {
        let size = CGSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        drawDiagonalResizeGlyph(start: start, end: end, strokeColor: .black, lineWidth: 4)
        drawDiagonalResizeGlyph(start: start, end: end, strokeColor: .white, lineWidth: 2)

        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    static func drawDiagonalResizeGlyph(start: CGPoint, end: CGPoint, strokeColor: NSColor, lineWidth: CGFloat) {
        strokeColor.setStroke()

        let body = NSBezierPath()
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.lineWidth = lineWidth
        body.move(to: start)
        body.line(to: end)
        body.stroke()

        drawArrowHead(at: start, toward: end, strokeColor: strokeColor, lineWidth: lineWidth)
        drawArrowHead(at: end, toward: start, strokeColor: strokeColor, lineWidth: lineWidth)
    }

    static func drawArrowHead(at tip: CGPoint, toward otherPoint: CGPoint, strokeColor: NSColor, lineWidth: CGFloat) {
        let dx = tip.x - otherPoint.x
        let dy = tip.y - otherPoint.y
        let length = max(1, hypot(dx, dy))
        let unit = CGPoint(x: dx / length, y: dy / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let base = CGPoint(x: tip.x - unit.x * 6, y: tip.y - unit.y * 6)
        let wing: CGFloat = 4

        let head = NSBezierPath()
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.lineWidth = lineWidth
        head.move(to: CGPoint(x: base.x + perpendicular.x * wing, y: base.y + perpendicular.y * wing))
        head.line(to: tip)
        head.line(to: CGPoint(x: base.x - perpendicular.x * wing, y: base.y - perpendicular.y * wing))
        head.stroke()
    }
}

