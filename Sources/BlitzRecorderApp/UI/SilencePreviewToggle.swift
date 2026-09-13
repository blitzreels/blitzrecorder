import SwiftUI

struct SilencePreviewToggle: View {
    @Bindable var session: SilenceEditingSession

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { preview; actions }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                preview
                HStack(spacing: 8) { actions }
            }
        }
    }

    private var preview: some View {
        Toggle("Preview without pauses", isOn: Binding(
            get: { session.skipSilence }, set: { session.setPreviewEnabled($0) }
        ))
        .toggleStyle(.blitzSwitch)
        .controlSize(.small)
        .disabled(!session.skipSilence && !session.canClassify)
        .help("Skip marked silence during playback only. Apply cuts to save them in the timeline and export.")
    }

    @ViewBuilder
    private var actions: some View {
        if session.metrics.hasChanges {
            Text("→ \(SilenceTime.label(session.metrics.outputDuration))")
                .monospacedDigit()
                .foregroundStyle(BlitzUI.secondaryText)
            Button("Apply cuts") { _ = session.apply() }
                .blitzButton(.accent)
                .controlSize(.small)
                .disabled(!session.canApply)
                .help("Save these cuts across all tracks and exports. Undo with ⌘Z.")
        } else if session.hasRemovedSilence {
            Text("Cuts saved").foregroundStyle(BlitzUI.secondaryText)
        }
        if session.preparingPreview {
            ProgressView().controlSize(.mini).help("Preparing silence preview")
        }
    }
}
