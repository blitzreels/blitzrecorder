import SwiftUI

struct BlitzMenuTriggerStyle: ButtonStyle {
    enum Variant {
        /// A dropdown field: a recessed well that always shows it can be opened.
        case field
        /// A toolbar icon or a part of a toolbar capsule: no resting fill, lit on hover and while open.
        case borderless
    }

    let isPresented: Bool
    var variant: Variant = .field
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BlitzControlMetrics.radius, style: .continuous)
        switch variant {
        case .field:
            configuration.label
                .background(BlitzUI.insetWell, in: shape)
                .background(
                    isPresented ? BlitzUI.selectedFill : (isHovering && isEnabled ? BlitzUI.quietFill : .clear),
                    in: shape
                )
                .overlay {
                    shape
                        .strokeBorder(isPresented ? BlitzUI.accent.opacity(0.5) : .clear, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .blitzFocusRing(cornerRadius: BlitzControlMetrics.radius)
                .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
                .contentShape(shape)
                .onHover { isHovering = $0 }
        case .borderless:
            configuration.label
                .background {
                    if isPresented || configuration.isPressed {
                        BlitzSelectedBackground(cornerRadius: BlitzControlMetrics.radius)
                    } else {
                        shape.fill(isHovering && isEnabled ? BlitzUI.quietFill : .clear)
                    }
                }
                .blitzFocusRing(cornerRadius: BlitzControlMetrics.radius)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(shape)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.1), value: isHovering)
        }
    }
}

struct BlitzMenuChevron: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(BlitzType.glyph(10))
            .foregroundStyle(BlitzUI.secondaryText)
            .accessibilityHidden(true)
    }
}
