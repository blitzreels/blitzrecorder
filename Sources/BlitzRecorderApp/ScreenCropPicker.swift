import AppKit
import CoreGraphics

enum ScreenCropPickerError: LocalizedError {
    case displayUnavailable
    case cancelled
    case selectionTooSmall

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "Selected display is not available."
        case .cancelled:
            return "Screen region selection cancelled."
        case .selectionTooSmall:
            return "Selected screen region is too small."
        }
    }
}

@MainActor
final class ScreenCropPicker {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGRect, Error>?

    func pick(displayID: String?) async throws -> CGRect {
        guard let screen = targetScreen(displayID: displayID) else {
            throw ScreenCropPickerError.displayUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let view = ScreenCropPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in
                self?.finish(with: .success(rect))
            }
            view.onCancel = { [weak self] in
                self?.finish(with: .failure(ScreenCropPickerError.cancelled))
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.window = window
        }
    }

    private func finish(with result: Result<CGRect, Error>) {
        window?.orderOut(nil)
        window = nil

        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case .success(let rect):
            continuation.resume(returning: rect)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func targetScreen(displayID: String?) -> NSScreen? {
        let selectedID = displayID.flatMap(UInt32.init) ?? CGMainDisplayID()
        return NSScreen.screens.first(where: { $0.displayID == selectedID }) ?? NSScreen.main
    }
}

@MainActor
private final class ScreenCropPickerView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var selection = CGRect.zero

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        startPoint = point
        selection = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        selection = normalizedRect(from: startPoint, to: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        let rect = normalizedRect(from: startPoint, to: point)
        self.startPoint = nil

        guard rect.width >= 160, rect.height >= 120 else {
            onFinish?(.null)
            return
        }

        onFinish?(normalizedCrop(from: rect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.58).setFill()
        bounds.fill()

        if !selection.isEmpty {
            NSColor.clear.setFill()
            selection.fill(using: .clear)

            NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 0.16).setFill()
            selection.fill()

            NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 1).setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 2
            border.stroke()
        }

        drawInstructions()
    }

    private func drawInstructions() {
        let text = "Drag to select screen region. Esc cancels."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 18,
            y: bounds.maxY - size.height - 56,
            width: size.width + 36,
            height: size.height + 20
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: rect.minX + 18, y: rect.minY + 10), withAttributes: attributes)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(bounds.maxX, max(bounds.minX, point.x)),
            y: min(bounds.maxY, max(bounds.minY, point.y))
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func normalizedCrop(from rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX / max(1, bounds.width),
            y: (bounds.height - rect.maxY) / max(1, bounds.height),
            width: rect.width / max(1, bounds.width),
            height: rect.height / max(1, bounds.height)
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.uint32Value
        }
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
