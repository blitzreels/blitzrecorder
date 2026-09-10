import AppKit
import SwiftUI

private struct BlitzCursorRegion: NSViewRepresentable {
    let cursor: NSCursor?

    func makeNSView(context: Context) -> CursorView {
        CursorView()
    }

    func updateNSView(_ view: CursorView, context: Context) {
        view.cursor = cursor
    }

    final class CursorView: NSView {
        var cursor: NSCursor? {
            didSet {
                guard oldValue !== cursor else { return }
                window?.invalidateCursorRects(for: self)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard let cursor, !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return }
            addCursorRect(visibleRect, cursor: cursor)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }
    }
}

private struct BlitzCursorModifier: ViewModifier {
    let cursor: NSCursor
    let enabled: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.background {
            BlitzCursorRegion(cursor: enabled && isEnabled ? cursor : nil)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func blitzCursor(_ cursor: NSCursor) -> some View {
        modifier(BlitzCursorModifier(cursor: cursor, enabled: true))
    }

    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(BlitzCursorModifier(cursor: .pointingHand, enabled: enabled))
    }
}
