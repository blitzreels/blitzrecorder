import AppKit
import SwiftUI

struct ProjectAIPromptButton: View {
    let context: ProjectAIPrompt.Context
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(ProjectAIPrompt.text(context), forType: .string)
        } label: {
            Label(copied ? "Copied" : "Copy AI context", systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .blitzButton(.dock)
        .accessibilityLabel(copied ? "Video context copied" : "Copy AI context")
        .help("Copy video details and MCP access instructions. Add your own request when you paste.")
        .task(id: copied) {
            guard copied else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                copied = false
            } catch {}
        }
        .onChange(of: context.projectId) { copied = false }
    }
}
