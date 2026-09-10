import SwiftUI

enum BlitzPreviewPreferences {
    static let animatePreviewsKey = "ui.animateSettingPreviews"
}

struct BlitzIllustratedLabel<Preview: View>: View {
    struct Configuration {
        let title: String
        let detail: String
        let preview: (Bool) -> Preview
    }

    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(BlitzPreviewPreferences.animatePreviewsKey) private var animatePreviews = true
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            configuration.preview(isHovering && isEnabled && animatePreviews)
                .frame(width: 80, height: 50)
                .background(BlitzUI.scenePreviewFill)
                .clipShape(.rect(cornerRadius: BlitzControlMetrics.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: BlitzControlMetrics.radius)
                        .strokeBorder(BlitzUI.separator, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BlitzUI.primaryText)
                Text(configuration.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(configuration.title)
        .accessibilityHint(configuration.detail)
    }
}
