import SwiftUI

struct EditorOutputPrimaryButton: View {
    struct Configuration {
        let title: String
        let systemImage: String
        let isEnabled: Bool
        let help: String
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            Label(configuration.title, systemImage: configuration.systemImage)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .blitzButton(.accent)
        .controlSize(.large)
        .disabled(!configuration.isEnabled)
        .help(configuration.help)
    }
}

struct EditorOutputSummary {
    let formats: String
    let resolution: OutputResolution
    let framesPerSecond: Int

    var text: String {
        [formats, resolution.displayName, "\(framesPerSecond) fps"].joined(separator: " · ")
    }
}
