import SwiftUI

struct ProjectAIPromptButton: View {
    let context: ProjectAIPrompt.Context

    var body: some View {
        BlitzCopyButton(configuration: .init(
            text: ProjectAIPrompt.text(context),
            title: "Copy AI context",
            accessibilityLabel: "Copy AI context",
            help: "Copy video details and MCP access instructions. Add your own request when you paste.",
            emphasis: .dock,
            width: .fit
        ))
    }
}
