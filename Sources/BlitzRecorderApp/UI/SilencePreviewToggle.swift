import SwiftUI

struct SilencePreviewToggle: View {
    @Bindable var session: SilenceEditingSession

    private var applyTitle: String {
        session.hasRemovedSilence || !session.metrics.hasChanges ? "Apply changes" : "Remove silence"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let activity = session.activity {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.title)
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.primaryText)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(activity.title)
                    Text(activity.detail)
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.supportingText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if session.hasChanges {
                    Button { _ = session.apply() } label: {
                        Label(applyTitle, systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                    }
                    .blitzButton(.accent)
                    .controlSize(.large)
                    .disabled(!session.canApply)
                    .help("Apply silence settings across all tracks and exports. Undo with ⌘Z.")
                    if session.metrics.outputDuration < 0.1 {
                        Text("Keep at least 0.1 seconds of the recording to apply these cuts.")
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Label(session.hasRemovedSilence ? "Silence removed" : "No silence to remove", systemImage: "checkmark.circle")
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.supportingText)
                }
                if session.hasRemovedSilence {
                    Button { session.restoreSilence() } label: {
                        Label("Restore removed silence", systemImage: "arrow.uturn.backward")
                    }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .disabled(session.isAuditioning)
                    .help("Restore removed silences across all tracks. Undo with ⌘Z.")
                }
            }
        }
    }
}
