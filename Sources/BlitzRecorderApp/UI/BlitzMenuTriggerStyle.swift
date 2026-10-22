import SwiftUI

struct BlitzMenuTriggerStyle: ButtonStyle {
    let isPresented: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(BlitzUI.insetWell, in: .rect(cornerRadius: BlitzControlMetrics.radius, style: .continuous))
            .background(
                isPresented ? BlitzUI.selectedFill : (isHovering && isEnabled ? BlitzUI.quietFill : .clear),
                in: .rect(cornerRadius: BlitzControlMetrics.radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzControlMetrics.radius, style: .continuous)
                    .strokeBorder(isPresented ? BlitzUI.accent.opacity(0.5) : .clear, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .blitzFocusRing(cornerRadius: BlitzControlMetrics.radius)
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: BlitzControlMetrics.radius))
            .onHover { isHovering = $0 }
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
