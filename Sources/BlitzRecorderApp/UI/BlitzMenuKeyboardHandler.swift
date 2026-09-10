import AppKit
import SwiftUI

enum BlitzMenuKeyboardCommand {
    case previous
    case next
    case select
    case dismiss

    struct Input {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
    }

    static func resolve(_ input: Input) -> Self? {
        guard input.modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch input.keyCode {
        case 126: return .previous
        case 125: return .next
        case 36, 76, 49: return .select
        case 53: return .dismiss
        default: return nil
        }
    }
}

struct BlitzMenuKeyboardHandler: NSViewRepresentable {
    let onCommand: (BlitzMenuKeyboardCommand) -> Void

    func makeNSView(context: Context) -> KeyView {
        KeyView(onCommand: onCommand)
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onCommand = onCommand
    }

    final class KeyView: NSView {
        var onCommand: (BlitzMenuKeyboardCommand) -> Void
        private var keyMonitor: Any?

        init(onCommand: @escaping (BlitzMenuKeyboardCommand) -> Void) {
            self.onCommand = onCommand
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            guard window != nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isVisible, let eventWindow = event.window,
                      eventWindow === window || eventWindow === window.parent || eventWindow === NSApp.mainWindow,
                      let command = BlitzMenuKeyboardCommand.resolve(.init(
                        keyCode: event.keyCode, modifiers: event.modifierFlags
                      )) else { return event }
                self.onCommand(command)
                return nil
            }
        }

        deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }
}
