import SwiftUI

@MainActor
func labeledDropdown<Value: Hashable>(_ configuration: BlitzDropdown<Value>.Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(configuration.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BlitzUI.secondaryText)
        BlitzDropdown(configuration: configuration)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
