import AppKit
import SwiftUI

struct BlitzGlassContainer<Content: View>: View {
    private let content: Content

    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

private struct BlitzGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let radius = min(cornerRadius, 10)
        // Flat: the material fill alone defines the panel. No stroke border — borders
        // on every surface read as "boxes inside boxes". (Native Tahoe look.)
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

private struct BlitzGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.075), in: Capsule())
    }
}

/// Canonical device-card / inspector-card surface: a FLAT fill over the .regularMaterial
/// rail (NOT glass-on-glass). Use this for on-rail cards; reserve `blitzGlassSurface`
/// for free-floating panels (TopBar, popovers, creator page).
private struct BlitzCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    var selected: Bool = false

    func body(content: Content) -> some View {
        // Selection reads from a brighter FILL (+ the mint icon/label inside), not a
        // mint outline. Flat fills, no stroke — the native segmented-control look.
        content
            .background(selected ? BlitzUI.selectedFill : BlitzUI.cardFill, in: .rect(cornerRadius: cornerRadius))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

extension View {
    func blitzGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(BlitzGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    func blitzGlassCapsule() -> some View {
        modifier(BlitzGlassCapsuleModifier())
    }

    func blitzCard(cornerRadius: CGFloat = 12, selected: Bool = false) -> some View {
        modifier(BlitzCardModifier(cornerRadius: cornerRadius, selected: selected))
    }

    func blitzSeparator() -> some View {
        self.overlay(BlitzUI.separator)
    }

    @ViewBuilder
    func blitzGlassButton() -> some View {
        self.buttonStyle(.bordered)
    }

    @ViewBuilder
    func blitzProminentGlassButton() -> some View {
        self.buttonStyle(.borderedProminent)
    }

    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}
