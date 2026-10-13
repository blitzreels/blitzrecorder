import AppKit
import SwiftUI

/// Right-click menus drawn by the app: glass, icons, the same rows as every other Blitz menu.
/// Opens at the pointer like a native menu and closes on Escape, a click elsewhere or a choice.
struct BlitzContextMenu {
    /// Runs first, e.g. to select the row that was right-clicked.
    let willOpen: () -> Void
    let entries: () -> [BlitzMenuEntry]
}

extension View {
    func blitzContextMenu(_ menu: BlitzContextMenu) -> some View {
        overlay {
            BlitzRightClickCatcher(onRightClick: {
                menu.willOpen()
                BlitzContextMenuPanel.shared.show(menu.entries())
            })
        }
    }
}

@MainActor
final class BlitzContextMenuPanel {
    static let shared = BlitzContextMenuPanel()

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private static let width: CGFloat = 236

    func show(_ entries: [BlitzMenuEntry]) {
        dismiss()
        guard !entries.isEmpty else { return }
        let pointer = NSEvent.mouseLocation
        let host = NSHostingView(rootView: BlitzContextMenuSurface(
            entries: entries, width: Self.width, dismiss: { [weak self] in self?.dismiss() }
        ))
        let size = host.fittingSize
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.appearance = NSApp.effectiveAppearance
        panel.contentView = host

        var origin = NSPoint(x: pointer.x + 2, y: pointer.y - size.height + 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame {
            origin.x = min(max(screen.minX + 4, origin.x), screen.maxX - size.width - 4)
            if origin.y < screen.minY + 4 { origin.y = min(pointer.y, screen.maxY - size.height - 4) }
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.dismiss(); return nil }
                return event
            }
            if event.window !== panel { self.dismiss() }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        monitors = [local, global].compactMap { $0 }
        observers = [resign]
    }

    func dismiss() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct BlitzContextMenuSurface: View {
    let entries: [BlitzMenuEntry]
    let width: CGFloat
    let dismiss: () -> Void

    var body: some View {
        BlitzMenuList(entries: entries, width: width, maxHeight: BlitzMenuList.adaptiveMaxHeight, dismiss: dismiss)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(.rect(cornerRadius: BlitzUI.cardRadius, style: .continuous))
            .overlay { BlitzEdgeHighlight(cornerRadius: BlitzUI.cardRadius) }
    }
}

/// Transparent to normal clicks; only right-clicks (and Control-clicks) land here.
private struct BlitzRightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var onRightClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isSecondary = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isSecondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick?() }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { onRightClick?() }
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }
    }
}
