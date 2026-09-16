import AppKit
import SwiftUI

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
