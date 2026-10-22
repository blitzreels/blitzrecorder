import AppKit
import SwiftUI

/// Soft light taken from the content itself, placed behind it.
struct BlitzAmbientGlow: View {
    let image: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 90)
                .saturation(colorScheme == .dark ? 1.7 : 2)
                .opacity(colorScheme == .dark ? 0.5 : 0.22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// System material behind a pane, so macOS draws the glass (and adopts Liquid Glass on Tahoe).
struct BlitzMaterialBackground: NSViewRepresentable {
    enum Kind {
        /// Navigation and tool columns: translucent sidebar material.
        case sidebar
        /// Lists that sit next to content.
        case content
    }

    let kind: Kind

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        switch kind {
        case .sidebar:
            view.material = .sidebar
            view.blendingMode = .behindWindow
        case .content:
            view.material = .contentBackground
            view.blendingMode = .withinWindow
        }
    }
}
