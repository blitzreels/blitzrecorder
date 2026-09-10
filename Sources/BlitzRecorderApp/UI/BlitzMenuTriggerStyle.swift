import SwiftUI

struct BlitzMenuTriggerStyle: ButtonStyle {
    let isPresented: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isHovering && isEnabled ? BlitzUI.hoverFill : BlitzUI.controlFill,
                in: .rect(cornerRadius: BlitzControlMetrics.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BlitzControlMetrics.radius)
                    .strokeBorder(isPresented ? BlitzUI.mint.opacity(0.65) : BlitzUI.panelStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: BlitzControlMetrics.radius))
            .onHover { isHovering = $0 }
            .pointingHandCursor()
    }
}

struct BlitzMenuChevron: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(BlitzUI.secondaryText)
            .accessibilityHidden(true)
    }
}
