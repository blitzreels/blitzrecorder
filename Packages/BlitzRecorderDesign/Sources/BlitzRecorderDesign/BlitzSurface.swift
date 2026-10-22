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
public struct BlitzSelectedBackground: View {
    let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [BlitzUI.raisedFillTop, BlitzUI.raisedFillBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { BlitzEdgeHighlight(cornerRadius: cornerRadius) }
            .shadow(color: BlitzUI.elevationShadow, radius: 2, y: 1)
    }
}

/// A one-pixel rim that is brighter at the top, so surfaces read as lit rather than outlined.
public struct BlitzEdgeHighlight<Rim: InsettableShape>: View {
    let shape: Rim

    public init(shape: Rim) {
        self.shape = shape
    }

    public var body: some View {
        shape
            .strokeBorder(LinearGradient(colors: [BlitzUI.edgeHighlight, BlitzUI.separator],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .allowsHitTesting(false)
    }
}

extension BlitzEdgeHighlight where Rim == RoundedRectangle {
    public init(cornerRadius: CGFloat) {
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
    public func blitzFieldChrome(isFocused: Bool) -> some View {
        modifier(BlitzFieldChromeModifier(isFocused: isFocused))
    }

    public func blitzGlass(cornerRadius: CGFloat) -> some View {
        modifier(BlitzGlassModifier(cornerRadius: cornerRadius))
    }
}

/// The one empty / error state: a quiet symbol, a title, a sentence, and at most one way forward.
public struct BlitzEmptyState: View {
    public struct Action {
        public let title: String
        public let run: () -> Void

        public init(title: String, run: @escaping () -> Void) {
            self.title = title
            self.run = run
        }
    }

    public struct Configuration {
        public let symbol: String
        public let title: String
        public let detail: String
        public let action: Action?

        public init(symbol: String, title: String, detail: String, action: Action?) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
            self.action = action
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public var body: some View {
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
public struct BlitzLoadingState: View {
    let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
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
