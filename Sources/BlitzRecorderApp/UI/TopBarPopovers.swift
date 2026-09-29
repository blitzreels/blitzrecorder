import SwiftUI

@MainActor
func labeledDropdown<Value: Hashable>(_ configuration: BlitzDropdown<Value>.Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(configuration.title)
            .font(BlitzType.captionEmphasis)
            .foregroundStyle(BlitzUI.secondaryText)
        BlitzDropdown(configuration: configuration)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
