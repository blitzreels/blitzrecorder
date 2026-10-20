import AppKit
import SwiftUI

private struct BlitzGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(BlitzUI.glassTint) }
            }
            .overlay { BlitzEdgeHighlight(cornerRadius: cornerRadius) }
            .shadow(color: BlitzUI.deepShadow, radius: 14, y: 6)
    }
}

/// Selected rows, tabs and tiles: a lit, slightly raised fill instead of a flat grey.
struct BlitzSelectedBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [BlitzUI.raisedFillTop, BlitzUI.raisedFillBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { BlitzEdgeHighlight(cornerRadius: cornerRadius) }
            .shadow(color: BlitzUI.elevationShadow, radius: 2, y: 1)
    }
}

/// A one-pixel rim that is brighter at the top, so surfaces read as lit rather than outlined.
struct BlitzEdgeHighlight<Rim: InsettableShape>: View {
    let shape: Rim

    var body: some View {
        shape
            .strokeBorder(LinearGradient(colors: [BlitzUI.edgeHighlight, BlitzUI.separator],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .allowsHitTesting(false)
    }
}

extension BlitzEdgeHighlight where Rim == RoundedRectangle {
    init(cornerRadius: CGFloat) {
        shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

/// Text fields: a soft fill, a hairline, and an accent ring while focused.
private struct BlitzFieldChromeModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        let radius = BlitzUI.cardRadius
        content
            .background(BlitzUI.controlFill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isFocused ? BlitzUI.accent.opacity(0.55) : BlitzUI.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                    .strokeBorder(BlitzUI.accent.opacity(isFocused ? 0.15 : 0), lineWidth: 3)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.1), value: isFocused)
    }
}

extension View {
    func blitzFieldChrome(isFocused: Bool) -> some View {
        modifier(BlitzFieldChromeModifier(isFocused: isFocused))
    }

    func blitzGlass(cornerRadius: CGFloat) -> some View {
        modifier(BlitzGlassModifier(cornerRadius: cornerRadius))
    }
}

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

/// The one empty / error state: a quiet symbol, a title, a sentence, and at most one way forward.
struct BlitzEmptyState: View {
    struct Action {
        let title: String
        let run: () -> Void
    }

    struct Configuration {
        let symbol: String
        let title: String
        let detail: String
        let action: Action?
    }

    let configuration: Configuration

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: configuration.symbol)
                .font(BlitzType.symbol(20))
                .foregroundStyle(BlitzUI.tertiaryText)
                .padding(.bottom, 4)
            Text(configuration.title)
                .font(BlitzType.headline)
                .foregroundStyle(BlitzUI.primaryText)
                .multilineTextAlignment(.center)
            Text(configuration.detail)
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action = configuration.action {
                Button(action.title, action: action.run)
                    .blitzButton(.secondary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 320)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The one loading state: a small spinner and what is loading, centered.
struct BlitzLoadingState: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(title)
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
