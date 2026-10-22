import AppKit
import SwiftUI

extension BlitzAppearanceMode {
    /// `nil` follows System Settings.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension BlitzAccentTheme {
    var nsAccent: NSColor { accentPair.nsColor }
}

extension BlitzThemeStore {
    /// The current tone's panel color, resolved at draw time so AppKit backgrounds follow tone changes too.
    static let panelNSColor = NSColor(name: nil) { appearance in
        let pair = BlitzThemeStore.shared.tint.palette.panel
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.dark : pair.light
    }

    @MainActor
    func applyAppearance() {
        NSApp.appearance = mode.nsAppearance
    }
}

// MARK: - Scrollers

extension NSScroller {
    /// Thin overlay scrollers everywhere, like a trackpad Mac, even when a mouse makes macOS fall back to wide legacy bars.
    static func useOverlayScrollersAppWide() {
        guard let original = class_getClassMethod(NSScroller.self, #selector(getter: NSScroller.preferredScrollerStyle)),
              let replacement = class_getClassMethod(NSScroller.self, #selector(NSScroller.blitzPreferredScrollerStyle))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    @objc private class func blitzPreferredScrollerStyle() -> NSScroller.Style { .overlay }
}
