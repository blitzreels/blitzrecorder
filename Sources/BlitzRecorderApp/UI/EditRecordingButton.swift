import SwiftUI

struct EditRecordingButton: View {
    struct Configuration {
        let title: String
        let isLoading: Bool
        let help: String
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 12) {
                Text(configuration.isLoading ? "Opening…" : configuration.title)
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(configuration.isLoading ? 0 : 0.65)
                    if configuration.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .environment(\.colorScheme, .light)
                    }
                }
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            }
            .fixedSize()
        }
        .blitzButton(.emphasized)
        .pointingHandCursor()
        .disabled(configuration.isLoading)
        .accessibilityLabel(configuration.isLoading ? "Opening recording" : configuration.title)
        .help(configuration.help)
    }
}
