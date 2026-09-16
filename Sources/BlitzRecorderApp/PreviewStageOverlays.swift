import AppKit

final class SceneSelectionOverlayView: NSView {
    static let handleRadius: CGFloat = 6

    var selectionFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var sourceFrame: NSRect? {
        didSet { needsDisplay = true }
    }
    var isCropMode = false {
        didSet { needsDisplay = true }
    }
    var showsResizeHandles = true {
        didSet { needsDisplay = true }
    }
    var canvasClip: NSRect? {
        didSet { needsDisplay = true }
    }

    func apply(_ appearance: PreviewStageSelection.Appearance) {
        isCropMode = appearance.isCropMode
        showsResizeHandles = appearance.showsResizeHandles
        selectionFrame = appearance.selectionFrame
        sourceFrame = appearance.sourceFrame
        canvasClip = appearance.canvasClip
        if let overlayFrame = appearance.overlayFrame {
            frame = overlayFrame
        }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let frame = selectionFrame else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let canvasClip, !canvasClip.isEmpty else { return }
        let shadeRegion = (isCropMode ? sourceFrame.map { canvasClip.union($0) } : nil) ?? canvasClip
        let clipRect = shadeRegion.insetBy(dx: -Self.handleRadius, dy: -Self.handleRadius)
        NSBezierPath(rect: clipRect).addClip()

        if isCropMode, let sourceFrame {
            drawCropShade(within: shadeRegion, cropFrame: frame)
            drawCropSourceOutline(sourceFrame)
        }

        let strokeColor = Brand.primary
        strokeColor.setStroke()
        let outerPath = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        outerPath.lineWidth = isCropMode ? 2 : 1.5
        if isCropMode {
            outerPath.setLineDash([8, 4], count: 2, phase: 0)
        }
        outerPath.stroke()

        if isCropMode {
            drawCropGrid(in: frame)
        }

        strokeColor.setFill()
        let handleConstraint = isCropMode ? sourceFrame : nil
        if showsResizeHandles {
            for grip in edgeGrips(for: frame, constrainedTo: handleConstraint).values {
                NSBezierPath(roundedRect: grip, xRadius: 2.5, yRadius: 2.5).fill()
            }
        }
        if showsResizeHandles {
            for handle in resizeHandles(for: frame, constrainedTo: handleConstraint).values {
                NSBezierPath(roundedRect: handle, xRadius: 3, yRadius: 3).fill()
                NSColor.black.withAlphaComponent(isCropMode ? 0.72 : 0.9).setStroke()
                let handleBorder = NSBezierPath(roundedRect: handle.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                handleBorder.lineWidth = 1
                handleBorder.stroke()
            }
        }
    }

    private func drawCropShade(within region: NSRect, cropFrame: NSRect) {
        NSColor.black.withAlphaComponent(0.58).setFill()
        let shade = NSBezierPath(rect: region)
        shade.append(NSBezierPath(rect: cropFrame).reversed)
        shade.fill()
    }

    private func drawCropSourceOutline(_ sourceFrame: NSRect) {
        NSColor.white.withAlphaComponent(0.38).setStroke()
        let sourcePath = NSBezierPath(rect: sourceFrame.insetBy(dx: 0.5, dy: 0.5))
        sourcePath.lineWidth = 1
        sourcePath.setLineDash([5, 4], count: 2, phase: 0)
        sourcePath.stroke()
    }

    private func drawCropGrid(in frame: NSRect) {
        NSColor.white.withAlphaComponent(0.40).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = frame.minX + frame.width * fraction
            grid.move(to: NSPoint(x: x, y: frame.minY))
            grid.line(to: NSPoint(x: x, y: frame.maxY))

            let y = frame.minY + frame.height * fraction
            grid.move(to: NSPoint(x: frame.minX, y: y))
            grid.line(to: NSPoint(x: frame.maxX, y: y))
        }
        grid.stroke()
    }

    private func resizeHandles(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        let size: CGFloat = 12
        let half = size / 2
        return [
            .topLeft: NSRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: NSRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: NSRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: NSRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ].mapValues { constrained($0, to: constraint) }
    }

    private func edgeGrips(for frame: NSRect, constrainedTo constraint: NSRect? = nil) -> [ResizeAnchor: NSRect] {
        [
            .top: NSRect(x: frame.midX - 18, y: frame.maxY - 2.5, width: 36, height: 5),
            .bottom: NSRect(x: frame.midX - 18, y: frame.minY - 2.5, width: 36, height: 5),
            .left: NSRect(x: frame.minX - 2.5, y: frame.midY - 18, width: 5, height: 36),
            .right: NSRect(x: frame.maxX - 2.5, y: frame.midY - 18, width: 5, height: 36)
        ].mapValues { constrained($0, to: constraint) }
    }

    private func constrained(_ rect: NSRect, to constraint: NSRect?) -> NSRect {
        guard let constraint, !constraint.isEmpty else { return rect }
        let width = min(rect.width, constraint.width)
        let height = min(rect.height, constraint.height)
        let minX = constraint.minX
        let maxX = constraint.maxX - width
        let minY = constraint.minY
        let maxY = constraint.maxY - height
        return NSRect(
            x: min(maxX, max(minX, rect.minX)),
            y: min(maxY, max(minY, rect.minY)),
            width: width,
            height: height
        )
    }

}

@MainActor
final class SafeZoneOverlayView: NSView {
    var showsRuleOfThirdsOverlay = false {
        didSet { needsDisplay = true }
    }

    var captureLayout: CaptureLayout = .vertical {
        didSet { needsDisplay = true }
    }

    var socialSafeZoneOverlay: SocialVideoSafeZone = .none {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if captureLayout == .vertical,
           let margins = socialSafeZoneOverlay.margins {
            drawSafeZone(margins: margins, title: socialSafeZoneOverlay.displayName)
        }

        guard showsRuleOfThirdsOverlay else { return }
        drawRuleOfThirds()
    }

    private func drawRuleOfThirds() {
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = bounds.minX + bounds.width * fraction
            grid.move(to: NSPoint(x: x, y: bounds.minY))
            grid.line(to: NSPoint(x: x, y: bounds.maxY))

            let y = bounds.minY + bounds.height * fraction
            grid.move(to: NSPoint(x: bounds.minX, y: y))
            grid.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        grid.stroke()
    }

    private func drawSafeZone(margins: VideoSafeZoneMargins, title: String) {
        let topHeight = bounds.height * margins.top
        let bottomHeight = bounds.height * margins.bottom
        let leftWidth = bounds.width * margins.left
        let rightWidth = bounds.width * margins.right

        let topRect = CGRect(x: bounds.minX, y: bounds.maxY - topHeight, width: bounds.width, height: topHeight)
        let bottomRect = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bottomHeight)
        let leftRect = CGRect(x: bounds.minX + leftWidth == bounds.minX ? bounds.minX : bounds.minX,
                              y: bounds.minY + bottomHeight,
                              width: leftWidth,
                              height: bounds.height - topHeight - bottomHeight)
        let rightRect = CGRect(x: bounds.maxX - rightWidth,
                               y: bounds.minY + bottomHeight,
                               width: rightWidth,
                               height: bounds.height - topHeight - bottomHeight)
        let safeRect = CGRect(
            x: bounds.minX + leftWidth,
            y: bounds.minY + bottomHeight,
            width: max(0, bounds.width - leftWidth - rightWidth),
            height: max(0, bounds.height - topHeight - bottomHeight)
        )

        NSColor.black.withAlphaComponent(0.58).setFill()
        [topRect, bottomRect, leftRect, rightRect].forEach { NSBezierPath(rect: $0).fill() }

        let mint = NSColor(red: 0.09, green: 1.0, blue: 0.65, alpha: 1)
        mint.setStroke()
        let safePath = NSBezierPath(roundedRect: safeRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8)
        safePath.lineWidth = 1.75
        safePath.lineCapStyle = .butt
        safePath.setLineDash([6, 4], count: 2, phase: 0)
        safePath.stroke()

        drawCornerTick(at: NSPoint(x: safeRect.minX, y: safeRect.maxY), corner: .topLeft, color: mint)
        drawCornerTick(at: NSPoint(x: safeRect.maxX, y: safeRect.maxY), corner: .topRight, color: mint)
        drawCornerTick(at: NSPoint(x: safeRect.minX, y: safeRect.minY), corner: .bottomLeft, color: mint)
        drawCornerTick(at: NSPoint(x: safeRect.maxX, y: safeRect.minY), corner: .bottomRight, color: mint)

        drawPlatformChip(title: title, in: safeRect)

        if topRect.height > 22 {
            drawRegionHint("UI overlay", in: topRect, alignment: .center)
        }
        if rightRect.width > 26 {
            drawRegionHint("Actions", in: rightRect, alignment: .vertical)
        }
        if bottomRect.height > 22 {
            drawRegionHint("Caption · CTA", in: bottomRect, alignment: .center)
        }
    }

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private func drawCornerTick(at point: NSPoint, corner: Corner, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        let length: CGFloat = 14
        switch corner {
        case .topLeft:
            path.move(to: NSPoint(x: point.x, y: point.y - length))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x + length, y: point.y))
        case .topRight:
            path.move(to: NSPoint(x: point.x - length, y: point.y))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x, y: point.y - length))
        case .bottomLeft:
            path.move(to: NSPoint(x: point.x, y: point.y + length))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x + length, y: point.y))
        case .bottomRight:
            path.move(to: NSPoint(x: point.x - length, y: point.y))
            path.line(to: point)
            path.line(to: NSPoint(x: point.x, y: point.y + length))
        }
        path.stroke()
    }

    private func drawPlatformChip(title: String, in safeRect: CGRect) {
        let label = "\(title) safe area"
        let font = NSFont.systemFont(ofSize: 10.5, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: 0.5
        ]
        let attributed = NSAttributedString(string: label.uppercased(), attributes: attributes)
        let labelSize = attributed.size()
        let chipWidth = labelSize.width + 18
        let chipHeight = labelSize.height + 8
        let x = safeRect.minX + 8
        let y = safeRect.maxY - chipHeight - 8
        let rect = CGRect(x: x, y: y, width: chipWidth, height: chipHeight)
        let mint = NSColor(red: 0.09, green: 1.0, blue: 0.65, alpha: 1)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: rect, xRadius: chipHeight / 2, yRadius: chipHeight / 2).fill()
        mint.withAlphaComponent(0.65).setStroke()
        let chipStroke = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: (chipHeight - 1.5) / 2, yRadius: (chipHeight - 1.5) / 2)
        chipStroke.lineWidth = 1
        chipStroke.stroke()

        let dotRadius: CGFloat = 3
        let dotRect = CGRect(x: rect.minX + 9 - dotRadius, y: rect.midY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        mint.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        attributed.draw(at: NSPoint(x: rect.minX + 9 + dotRadius + 6, y: rect.minY + 4))
    }

    enum HintAlignment { case center, vertical }

    private func drawRegionHint(_ text: String, in rect: CGRect, alignment: HintAlignment) {
        let font = NSFont.systemFont(ofSize: 10.5, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.78),
            .kern: 0.8
        ]
        let attributed = NSAttributedString(string: text.uppercased(), attributes: attributes)
        let labelSize = attributed.size()

        switch alignment {
        case .center:
            let x = rect.midX - labelSize.width / 2
            let y = rect.midY - labelSize.height / 2
            attributed.draw(at: NSPoint(x: x, y: y))
        case .vertical:
            NSGraphicsContext.current?.saveGraphicsState()
            let context = NSGraphicsContext.current?.cgContext
            context?.translateBy(x: rect.midX, y: rect.midY)
            context?.rotate(by: -.pi / 2)
            let x = -labelSize.width / 2
            let y = -labelSize.height / 2
            attributed.draw(at: NSPoint(x: x, y: y))
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}

