import AppKit
import CoreGraphics

enum ScreenCropPickerError: LocalizedError {
    case displayUnavailable
    case cancelled
    case selectionTooSmall
    case selectionInProgress

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "Selected display is not available."
        case .cancelled:
            return "Screen region selection cancelled."
        case .selectionTooSmall:
            return "Selected screen region is too small."
        case .selectionInProgress:
            return "Screen region selection is already open."
        }
    }
}

@MainActor
final class ScreenCropPicker {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGRect, Error>?

    func pick(displayID: String?, initialCrop: CGRect? = nil) async throws -> CGRect {
        guard continuation == nil else {
            throw ScreenCropPickerError.selectionInProgress
        }
        guard let screen = targetScreen(displayID: displayID) else {
            throw ScreenCropPickerError.displayUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let view = ScreenCropPickerView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                initialCrop: initialCrop
            )
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

    private enum DragIntent {
        case create
        case move(startRect: CGRect)
        case resize(ResizeAnchor, startRect: CGRect)
    }

    private var startPoint: CGPoint?
    private var dragIntent: DragIntent?
    private var selection = CGRect.zero
    private let toolbar = NSView()
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame frameRect: NSRect, initialCrop: CGRect?) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        selection = initialCrop.map { Self.rect(fromNormalizedCrop: $0, in: frameRect.size) } ?? .zero
        configureToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateToolbar()
    }

    override func layout() {
        super.layout()
        updateToolbar()
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        startPoint = point
        if let anchor = resizeAnchor(at: point, in: selection) {
            dragIntent = .resize(anchor, startRect: selection)
        } else if selection.contains(point), isSelectionValid {
            dragIntent = .move(startRect: selection)
        } else {
            dragIntent = .create
            selection = CGRect(origin: point, size: .zero)
        }
        needsDisplay = true
        updateToolbar()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint, let dragIntent else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        switch dragIntent {
        case .create:
            selection = normalizedRect(from: startPoint, to: point)
        case .move(let startRect):
            let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            selection = clamped(startRect.offsetBy(dx: delta.x, dy: delta.y))
        case .resize(let anchor, let startRect):
            let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            selection = resized(startRect, delta: delta, anchor: anchor)
        }
        needsDisplay = true
        updateToolbar()
    }

    override func mouseUp(with event: NSEvent) {
        self.startPoint = nil
        dragIntent = nil
        needsDisplay = true
        updateToolbar()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else if event.keyCode == 36, isSelectionValid {
            onFinish?(normalizedCrop(from: selection))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.58).setFill()
        bounds.fill()

        if isSelectionVisible {
            NSColor.clear.setFill()
            selection.fill(using: .clear)

            NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 0.16).setFill()
            selection.fill()

            NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 1).setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 2
            border.stroke()
            drawCropGrid(in: selection)
            drawHandles(in: selection)
            drawCropLabel(in: selection)
        }

        drawInstructions()
    }

    private func drawInstructions() {
        let text = "Crop Mode - drag to create or edit the capture crop. Return applies. Esc cancels."
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

    private func configureToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        toolbar.layer?.cornerRadius = 9
        toolbar.layer?.cornerCurve = .continuous
        addSubview(toolbar)

        for button in [applyButton, resetButton, cancelButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            toolbar.addSubview(button)
        }
        applyButton.target = self
        applyButton.action = #selector(applyCrop)
        resetButton.target = self
        resetButton.action = #selector(resetCrop)
        cancelButton.target = self
        cancelButton.action = #selector(cancelCrop)
    }

    private func updateToolbar() {
        toolbar.isHidden = !isSelectionVisible
        applyButton.isEnabled = isSelectionValid
        guard isSelectionVisible else { return }

        let buttonHeight: CGFloat = 28
        let buttonY: CGFloat = 8
        let sizes: [(NSButton, CGFloat)] = [
            (applyButton, 62),
            (resetButton, 62),
            (cancelButton, 70)
        ]
        var x: CGFloat = 8
        for (button, width) in sizes {
            button.frame = CGRect(x: x, y: buttonY, width: width, height: buttonHeight)
            x += width + 6
        }

        let toolbarSize = CGSize(width: x + 2, height: 44)
        var origin = CGPoint(
            x: min(bounds.maxX - toolbarSize.width - 16, max(bounds.minX + 16, selection.midX - toolbarSize.width / 2)),
            y: selection.maxY + 12
        )
        if origin.y + toolbarSize.height > bounds.maxY - 16 {
            origin.y = max(bounds.minY + 16, selection.minY - toolbarSize.height - 12)
        }
        toolbar.frame = CGRect(origin: origin, size: toolbarSize)
    }

    @objc private func applyCrop() {
        guard isSelectionValid else { return }
        onFinish?(normalizedCrop(from: selection))
    }

    @objc private func resetCrop() {
        selection = bounds
        needsDisplay = true
        updateToolbar()
    }

    @objc private func cancelCrop() {
        onCancel?()
    }

    private var isSelectionVisible: Bool {
        selection.width > 1 && selection.height > 1
    }

    private var isSelectionValid: Bool {
        selection.width >= 160 && selection.height >= 120
    }

    private func drawCropLabel(in frame: CGRect) {
        let text = "Capture crop"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: frame.minX + 10,
            y: min(bounds.maxY - size.height - 12, frame.maxY + 8),
            width: size.width + 18,
            height: size.height + 10
        )
        NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: rect.minX + 9, y: rect.minY + 5), withAttributes: attributes)
    }

    private func drawCropGrid(in frame: CGRect) {
        NSColor.white.withAlphaComponent(0.42).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = frame.minX + frame.width * fraction
            grid.move(to: CGPoint(x: x, y: frame.minY))
            grid.line(to: CGPoint(x: x, y: frame.maxY))

            let y = frame.minY + frame.height * fraction
            grid.move(to: CGPoint(x: frame.minX, y: y))
            grid.line(to: CGPoint(x: frame.maxX, y: y))
        }
        grid.stroke()
    }

    private func drawHandles(in frame: CGRect) {
        NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 1).setFill()
        for handle in resizeHandles(for: frame).values {
            NSBezierPath(roundedRect: handle, xRadius: 3, yRadius: 3).fill()
        }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(bounds.maxX, max(bounds.minX, point.x)),
            y: min(bounds.maxY, max(bounds.minY, point.y))
        )
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        let width = min(bounds.width, max(1, rect.width))
        let height = min(bounds.height, max(1, rect.height))
        let x = min(bounds.maxX - width, max(bounds.minX, rect.minX))
        let y = min(bounds.maxY - height, max(bounds.minY, rect.minY))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func resized(_ rect: CGRect, delta: CGPoint, anchor: ResizeAnchor) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        if anchor.resizesLeftEdge { minX += delta.x }
        if anchor.resizesRightEdge { maxX += delta.x }
        if anchor.resizesBottomEdge { minY += delta.y }
        if anchor.resizesTopEdge { maxY += delta.y }

        if maxX - minX < 160 {
            if anchor.resizesLeftEdge { minX = maxX - 160 } else { maxX = minX + 160 }
        }
        if maxY - minY < 120 {
            if anchor.resizesBottomEdge { minY = maxY - 120 } else { maxY = minY + 120 }
        }

        return clamped(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
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

    private func resizeAnchor(at point: CGPoint, in frame: CGRect) -> ResizeAnchor? {
        resizeHandles(for: frame).first { $0.value.contains(point) }?.key
    }

    private func resizeHandles(for frame: CGRect) -> [ResizeAnchor: CGRect] {
        guard isSelectionVisible else { return [:] }
        let size: CGFloat = 18
        let half = size / 2
        return [
            .topLeft: CGRect(x: frame.minX - half, y: frame.maxY - half, width: size, height: size),
            .topRight: CGRect(x: frame.maxX - half, y: frame.maxY - half, width: size, height: size),
            .bottomLeft: CGRect(x: frame.minX - half, y: frame.minY - half, width: size, height: size),
            .bottomRight: CGRect(x: frame.maxX - half, y: frame.minY - half, width: size, height: size)
        ]
    }

    private static func rect(fromNormalizedCrop crop: CGRect, in size: CGSize) -> CGRect {
        let crop = crop.standardized
        let width = crop.width * size.width
        let height = crop.height * size.height
        return CGRect(
            x: crop.minX * size.width,
            y: size.height - crop.maxY * size.height,
            width: width,
            height: height
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
