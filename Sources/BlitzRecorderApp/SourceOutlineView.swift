import AppKit

@MainActor
final class SourceOutlineView: NSView {
    var sourceFrames: [NSRect] = [] { didSet { needsDisplay = true } }
    var canvasFrame: NSRect = .zero { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !sourceFrames.isEmpty, !canvasFrame.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let margin = canvasFrame.insetBy(dx: -SceneSelectionOverlayView.handleRadius,
                                         dy: -SceneSelectionOverlayView.handleRadius)
        let outsideCanvas = NSBezierPath(rect: margin)
        outsideCanvas.append(NSBezierPath(rect: canvasFrame).reversed)
        outsideCanvas.addClip()

        NSColor.white.withAlphaComponent(0.4).setStroke()
        for rect in sourceFrames where !rect.isEmpty {
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            let pattern: [CGFloat] = [4, 3]
            path.setLineDash(pattern, count: 2, phase: 0)
            path.stroke()
        }
    }
}
