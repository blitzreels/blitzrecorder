import SwiftUI

struct BlitzFormDropdown<Value: Hashable>: View {
    let configuration: BlitzDropdown<Value>.Configuration

    var body: some View {
        HStack(spacing: 16) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 88, alignment: .leading)
            BlitzDropdown(configuration: configuration)
        }
        .frame(minHeight: BlitzControlMetrics.height(.regular))
    }
}
