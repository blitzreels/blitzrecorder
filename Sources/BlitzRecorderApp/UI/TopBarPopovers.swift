import SwiftUI

@MainActor
func labeledDropdown<Value: Hashable>(_ configuration: BlitzDropdown<Value>.Configuration) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        BlitzUI.sectionLabel(configuration.title)
        BlitzDropdown(configuration: configuration)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
