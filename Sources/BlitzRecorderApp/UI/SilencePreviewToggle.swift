import SwiftUI

struct SilencePreviewToggle: View {
    enum Presentation {
        case inline
        case inspector
    }

    struct Configuration {
        let session: SilenceEditingSession
        let presentation: Presentation
    }

    @Bindable private var session: SilenceEditingSession
    private let presentation: Presentation

    init(configuration: Configuration) {
        self.session = configuration.session
        self.presentation = configuration.presentation
    }

    var body: some View {
        if presentation == .inspector {
            VStack(alignment: .leading, spacing: 4) {
                if session.metrics.hasChanges {
                    applyButton
                }
                if session.hasRemovedSilence {
                    HStack(spacing: 12) {
                        if !session.metrics.hasChanges {
                            Label("Cuts saved", systemImage: "checkmark")
                                .font(.system(size: 12))
                                .foregroundStyle(BlitzUI.supportingText)
                        }
                        Spacer(minLength: 0)
                        Button("Restore") { session.restoreSilence() }
                            .blitzButton(.quiet)
                            .controlSize(.regular)
                            .disabled(session.loading || session.calculating || session.preparingPreview)
                            .accessibilityLabel("Restore removed silence")
                            .help("Restore removed pauses across all tracks. Undo with ⌘Z.")
                    }
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { preview; actions }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) {
                    preview
                    HStack(spacing: 8) { actions }
                }
            }
        }
    }

    private var preview: some View {
        Toggle("Preview without pauses", isOn: Binding(
            get: { session.skipSilence }, set: { session.setPreviewEnabled($0) }
        ))
        .toggleStyle(.blitzSwitch)
        .controlSize(presentation == .inspector ? .large : .small)
        .disabled(!session.skipSilence && !session.canClassify)
        .help("Skip marked silence during playback only. Apply cuts to save them in the timeline and export.")
    }

    @ViewBuilder
    private var actions: some View {
        if session.metrics.hasChanges {
            Text("→ \(SilenceTime.label(session.metrics.outputDuration))")
                .monospacedDigit()
                .foregroundStyle(BlitzUI.secondaryText)
            applyButton
        } else if session.hasRemovedSilence {
            Text("Cuts saved").foregroundStyle(BlitzUI.secondaryText)
        }
        if session.preparingPreview {
            ProgressView().controlSize(.mini).help("Preparing silence preview")
        }
    }

    private var applyButton: some View {
        Button { _ = session.apply() } label: {
            Text("Apply cuts")
                .frame(maxWidth: presentation == .inspector ? .infinity : nil)
        }
        .blitzButton(.accent)
        .controlSize(presentation == .inspector ? .large : .small)
        .disabled(!session.canApply)
        .help("Save these cuts across all tracks and exports. Undo with ⌘Z.")
    }
}
