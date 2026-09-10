import SwiftUI

struct SilencePreviewToggle: View {
    @Bindable var session: SilenceEditingSession

    var body: some View {
        HStack(spacing: 8) {
            Toggle(
                "Ignore silent segments",
                isOn: Binding(get: { session.skipSilence }, set: { session.setPreviewEnabled($0) })
            )
            .toggleStyle(.blitzSwitch)
            .controlSize(.small)
            .disabled(!session.skipSilence && !session.canClassify)
            .help("Skip marked silence during playback only. Apply silence cuts to save them in the timeline and export.")
            if session.preparingPreview {
                ProgressView().controlSize(.mini).help("Preparing silence preview")
            }
        }
    }
}
