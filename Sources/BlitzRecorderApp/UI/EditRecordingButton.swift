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
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "slider.horizontal.below.rectangle")
                        .opacity(configuration.isLoading ? 0 : 1)
                    if configuration.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .environment(\.colorScheme, .light)
                    }
                }
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
                Text(configuration.isLoading ? "Opening…" : configuration.title)
            }
            .fixedSize()
        }
        .blitzButton(.accent)
        .pointingHandCursor()
        .disabled(configuration.isLoading)
        .accessibilityLabel(configuration.isLoading ? "Opening recording" : configuration.title)
        .help(configuration.help)
    }
}
