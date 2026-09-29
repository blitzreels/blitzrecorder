import AppKit
import SwiftUI

struct EditorTimelineKeyboardFocus: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    func makeNSView(context: Context) -> FocusView { FocusView() }

    func updateNSView(_ nsView: FocusView, context: Context) {
        nsView.isEnabled = isEnabled
    }

    final class FocusView: NSView {
        var isEnabled = true
        private var mouseMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            guard window != nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.focusForTimelineClick(event)
                return event
            }
        }

        deinit {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }

        func focusForTimelineClick(_ event: NSEvent) {
            guard isEnabled, event.type == .leftMouseDown, let window, event.window === window,
                window.attachedSheet == nil, NSApp.modalWindow == nil,
                !isHiddenOrHasHiddenAncestor,
                bounds.contains(convert(event.locationInWindow, from: nil)),
                visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return }
            window.makeFirstResponder(self)
        }
    }
}

struct EditorKeyboardShortcutView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ShortcutView {
        let view = ShortcutView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: ShortcutView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }

    final class ShortcutView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        private var keyMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installKeyMonitorIfNeeded()
        }

        deinit {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        private func installKeyMonitorIfNeeded() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                    window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil,
                    EditorKeyboardCommand.acceptsShortcuts(firstResponder: window.firstResponder)
                else {
                    return event
                }
                return self.onKeyDown?(event) == true ? nil : event
            }
        }
    }
}
