import AppKit

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            let view = RuleOfThirdsView(frame: NSScreen.main?.frame ?? .zero)
            let window = NSWindow(
                contentRect: NSScreen.main?.frame ?? .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = view
            self.window = window
        }
        window?.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }
}

final class RuleOfThirdsView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        let path = NSBezierPath()
        path.lineWidth = 1.5

        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = bounds.width * fraction
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.height))

            let y = bounds.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: bounds.width, y: y))
        }

        NSColor.systemYellow.withAlphaComponent(0.55).setStroke()
        path.stroke()

        let center = NSBezierPath(ovalIn: CGRect(x: bounds.midX - 5, y: bounds.midY - 5, width: 10, height: 10))
        NSColor.systemRed.withAlphaComponent(0.8).setFill()
        center.fill()
    }
}
