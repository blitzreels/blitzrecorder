import SwiftUI

struct TranscriptSpeakerLabel: View {
    struct Configuration {
        let speaker: RecordingTranscript.Speaker
        let color: Color
        let onRename: (TranscriptSpeakerRenameRequest) -> Void
    }

    let configuration: Configuration
    @State private var isRenaming = false
    @State private var draft = ""
    @State private var rememberVoice = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Button(action: beginRename) {
            HStack(spacing: 6) {
                Circle()
                    .fill(configuration.color.opacity(0.75))
                    .frame(width: 5, height: 5)
                Text(configuration.speaker.displayName)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(1)
                if let suggestion = configuration.speaker.identitySuggestion {
                    Text("\(suggestion.name)? · \(suggestion.label)")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.mint)
                        .lineLimit(1)
                }
            }
        }
        .blitzButton(.quiet)
        .controlSize(.mini)
        .help("Rename \(configuration.speaker.displayName) or remember their voice")
        .accessibilityLabel("Speaker \(configuration.speaker.displayName)")
        .accessibilityHint("Rename this speaker or review a suggested identity")
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
            if let suggestion = configuration.speaker.identitySuggestion {
                Text("Suggested: \(suggestion.name) · \(suggestion.label)")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.mint)
                Text(suggestion.evidence)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(4)
            }
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
            Toggle("Remember this voice on this Mac", isOn: $rememberVoice)
                .toggleStyle(.blitzCheckbox)
                .disabled(configuration.speaker.voice?.isUsable != true)
            Text(configuration.speaker.voice?.isUsable == true
                 ? "Suggest this name in future recordings. Saved only when you choose Save."
                 : "Run Fix speakers to collect a voice sample. At least three seconds of speech are needed.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if configuration.speaker.savedVoiceID != nil {
                Button("Forget saved voice", role: .destructive) {
                    isRenaming = false
                    configuration.onRename(.init(speakerID: configuration.speaker.id,
                                                 name: configuration.speaker.name, voiceMemory: .forget))
                }
                .blitzButton(.secondary)
                .controlSize(.small)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { isRenaming = false } label: { Label("Cancel", systemImage: "xmark") }
                    .blitzButton(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: commit) { Label("Save", systemImage: "checkmark") }
                    .blitzButton(.accent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (rememberVoice && draft.trimmingCharacters(in: .whitespacesAndNewlines) == "You"))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(BlitzUI.panelBackground)
        .onAppear { isFieldFocused = true }
    }

    private func beginRename() {
        draft = configuration.speaker.identitySuggestion?.name ?? configuration.speaker.name
        rememberVoice = configuration.speaker.savedVoiceID != nil
        isRenaming = true
    }

    private func commit() {
        isRenaming = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        configuration.onRename(.init(speakerID: configuration.speaker.id, name: name,
                                     voiceMemory: rememberVoice ? .remember : .unchanged,
                                     profileID: configuration.speaker.savedVoiceID
                                        ?? (name == configuration.speaker.identitySuggestion?.name
                                            ? configuration.speaker.identitySuggestion?.profileID : nil)))
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
