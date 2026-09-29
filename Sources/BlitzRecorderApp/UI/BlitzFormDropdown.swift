import SwiftUI

struct BlitzFormDropdown<Value: Hashable>: View {
    let configuration: BlitzDropdown<Value>.Configuration

    var body: some View {
        HStack(spacing: 16) {
            Text(configuration.title)
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 88, alignment: .leading)
            BlitzDropdown(configuration: configuration)
        }
        .frame(minHeight: BlitzControlMetrics.height(.regular))
    }
}
