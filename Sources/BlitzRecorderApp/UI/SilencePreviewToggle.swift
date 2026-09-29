import SwiftUI

struct SilencePreviewToggle: View {
    @Bindable var session: SilenceEditingSession

    private enum Stage: CaseIterable {
        case before
        case after

        var title: String {
            switch self {
            case .before: "Before"
            case .after: "After"
            }
        }

        var symbolName: String {
            switch self {
            case .before: "waveform"
            case .after: "scissors"
            }
        }
    }

    private var comparesCuts: Bool { session.hasChanges || session.skipSilence }

    private var applyTitle: String {
        if session.hasChanges {
            return session.hasRemovedSilence || !session.metrics.hasChanges ? "Apply changes" : "Remove silence"
        }
        return session.hasRemovedSilence ? "Silence removed" : "Nothing to remove"
    }

    var body: some View {
        VStack(spacing: 10) {
            Button { _ = session.apply() } label: {
                Label(applyTitle, systemImage: session.hasChanges ? "scissors" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.accent)
            .controlSize(.large)
            .disabled(!session.hasChanges || !session.canApply)
            .help("Apply silence settings across all tracks and exports. Undo with ⌘Z.")
            HStack(spacing: 8) {
                Group {
                    BlitzSegmentedPicker(configuration: .init(
                        title: "Silence preview",
                        options: Stage.allCases,
                        selection: Binding(
                            get: { session.skipSilence ? .after : .before },
                            set: { session.setPreviewEnabled($0 == .after) }
                        ),
                        label: { $0.title },
                        symbolName: { $0.symbolName }
                    ))
                    .controlSize(.small)
                    .disabled(!comparesCuts || session.isAuditioning || (!session.skipSilence && !session.canClassify))
                    .help("Preview the timeline before or after the marked silences are cut. Apply changes to keep them.")
                }
                if session.hasRemovedSilence {
                    Button { session.restoreSilence() } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(session.isAuditioning || session.loading || session.calculating || session.preparingPreview)
                    .accessibilityLabel("Restore removed silence")
                    .help("Restore removed silences across all tracks. Undo with ⌘Z.")
                }
            }
        }
    }
}
