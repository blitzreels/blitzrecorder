import SwiftUI

struct SilencePreviewToggle: View {
    @Bindable var session: SilenceEditingSession

    var body: some View {
        VStack(spacing: 10) {
            if session.hasChanges || session.skipSilence {
                Toggle("Preview cuts", isOn: Binding(
                    get: { session.skipSilence }, set: { session.setPreviewEnabled($0) }
                ))
                .toggleStyle(.blitzSwitch)
                .controlSize(.regular)
                .disabled(session.isAuditioning || (!session.skipSilence && !session.canClassify))
                .help("Preview marked silences as removed. Apply changes to save them in the timeline and export.")
            }
            if session.hasChanges {
                Button { _ = session.apply() } label: {
                    Text(session.hasRemovedSilence || !session.metrics.hasChanges ? "Apply changes" : "Remove silence")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.accent)
                .controlSize(.large)
                .disabled(!session.canApply)
                .help("Apply silence settings across all tracks and exports. Undo with ⌘Z.")
            }
            if session.hasChanges || session.hasRemovedSilence {
                HStack(spacing: 8) {
                    if session.hasChanges {
                        Text("All tracks · ⌘Z to undo")
                            .font(.system(size: 11))
                            .foregroundStyle(BlitzUI.supportingText)
                    } else {
                        Label("Silence removed", systemImage: "checkmark")
                            .font(.system(size: 12))
                            .foregroundStyle(BlitzUI.supportingText)
                    }
                    Spacer(minLength: 0)
                    if session.hasRemovedSilence {
                        Button("Restore silence") { session.restoreSilence() }
                            .blitzButton(.quiet)
                            .controlSize(.small)
                            .disabled(session.isAuditioning || session.loading || session.calculating || session.preparingPreview)
                            .accessibilityLabel("Restore removed silence")
                            .help("Restore removed silences across all tracks. Undo with ⌘Z.")
                    }
                }
            }
        }
    }
}
