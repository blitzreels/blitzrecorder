import SwiftUI

struct TranscriptSpeakerLabel: View {
    struct Configuration {
        let name: String
        let currentName: String
        let color: Color
        let onRename: (String) -> Void
    }

    let configuration: Configuration
    @State private var isRenaming = false
    @State private var isHovering = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Button(action: beginRename) {
            HStack(spacing: 6) {
                Circle()
                    .fill(configuration.color.opacity(0.75))
                    .frame(width: 5, height: 5)
                Text(configuration.name)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(isHovering || isRenaming ? BlitzUI.primaryText : BlitzUI.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(isHovering || isRenaming ? BlitzUI.hoverFill : .clear,
                        in: .rect(cornerRadius: BlitzUI.controlRadius))
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .padding(.leading, -6)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help("Rename \(configuration.name)")
        .accessibilityLabel("Speaker \(configuration.name)")
        .accessibilityHint("Rename this speaker")
        .contextMenu {
            Button("Rename Speaker…", systemImage: "pencil", action: beginRename)
        }
        .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
            renameEditor
        }
    }

    private var renameEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename speaker")
                .font(BlitzType.section)
                .foregroundStyle(BlitzUI.primaryText)
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(BlitzType.body)
                .focused($isFieldFocused)
                .onSubmit(commit)
                .padding(.horizontal, 10)
                .frame(height: BlitzControlMetrics.height(.regular))
                .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: BlitzControlMetrics.radius, style: .continuous)
                        .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
                }
            Text("Used everywhere this transcript shows speakers, and when you copy it.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { isRenaming = false } label: { Label("Cancel", systemImage: "xmark") }
                    .blitzButton(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: commit) { Label("Save", systemImage: "checkmark") }
                    .blitzButton(.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(BlitzUI.panelBackground)
        .onAppear { isFieldFocused = true }
    }

    private func beginRename() {
        draft = configuration.currentName
        isRenaming = true
    }

    private func commit() {
        isRenaming = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != configuration.currentName.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        configuration.onRename(name)
    }
}

struct TranscriptTimestampButton: View {
    let timestamp: String
    let isEnabled: Bool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(timestamp)
                .font(BlitzType.caption.monospaced())
                .monospacedDigit()
                .foregroundStyle(isActive ? BlitzUI.mint : BlitzUI.secondaryText)
                .frame(width: 52, height: 24, alignment: .leading)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
        .disabled(!isEnabled)
        .pointingHandCursor(enabled: isEnabled)
        .help("Play from \(timestamp)")
        .accessibilityLabel("Play transcript from \(timestamp)")
    }
}
