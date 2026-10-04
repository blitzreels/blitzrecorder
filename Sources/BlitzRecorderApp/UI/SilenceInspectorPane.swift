import SwiftUI

enum SilencePacing: Int, CaseIterable {
    case natural = 1
    case tight = 2
    case rapid = 3
}

struct SilenceInspectorPane: View {
    @Bindable var session: SilenceEditingSession
    @State private var showsTuning = false
    @State private var phaseStartedAt = Date()

    var body: some View {
        let presentation = session.presentation
        let actions = SilencePaneActions(
            apply: { _ = session.apply() },
            restore: session.restoreSilence,
            setPreview: session.setPreviewEnabled,
            selectStrength: session.selectStrength
        )
        EditorInspectorPane(configuration: .init(
            title: "Silence",
            detail: "Cut the long pauses between phrases. Words are never cut.",
            showsFooter: presentation.phase.showsFooter,
            content: {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    SilenceSummaryCard(presentation: presentation, phaseStartedAt: phaseStartedAt)
                    SilenceStrengthSection(presentation: presentation, actions: actions)
                    BlitzInspectorDisclosure(configuration: .init(
                        title: "Fine-tune",
                        detail: session.customized ? "Custom" : nil,
                        isExpanded: $showsTuning,
                        content: { tuning }
                    ))
                    .disabled(!presentation.hasResult)
                }
            },
            footer: { SilenceFooterActions(presentation: presentation, actions: actions) }
        ))
        .onChange(of: presentation.phase.kind) { phaseStartedAt = Date() }
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                BlitzInspectorHeading(configuration: .init(title: "Detection", detail: session.sourceName))
                Toggle("Automatic threshold", isOn: Binding(
                    get: { session.automaticThreshold },
                    set: { session.automaticThreshold = $0; session.changeThresholdMode() }
                ))
                    .toggleStyle(.blitzSwitch)
                BlitzInspectorSlider(configuration: .init(
                    title: "Threshold", value: Binding(
                        get: { session.threshold },
                        set: { session.threshold = $0; session.recalculate() }
                    ), range: -70 ... -15, step: 1,
                    valueLabel: "\(Int(session.threshold)) dB",
                    onEditingChanged: { _ in },
                    onReset: { session.threshold = SilenceEditingSession.defaultThreshold; session.recalculate() }
                ))
                .disabled(session.automaticThreshold)

            }
            parameter(.init(title: "Minimum pause", detail: "Only consider quiet gaps at least this long.",
                            value: $session.minimumDuration, range: 0.1...3))
            VStack(alignment: .leading, spacing: 12) {
                BlitzInspectorHeading(configuration: .init(title: "Breathing room", detail: nil))
                Toggle("Same before and after", isOn: Binding(
                    get: { session.linkedPadding },
                    set: { linked in
                        session.linkedPadding = linked
                        if linked { session.paddingAfter = session.paddingBefore }
                        session.customized = true
                        session.recalculate()
                    }
                ))
                    .toggleStyle(.blitzCheckbox)
                    .controlSize(.small)
                    .accessibilityLabel("Link silence padding")
                parameter(.init(title: session.linkedPadding ? "Around speech" : "Before speech",
                                detail: "Keep this much silence on each side of speech. Shorter gaps stay intact.",
                                value: Binding(
                                    get: { session.paddingBefore },
                                    set: { value in
                                        session.paddingBefore = value
                                        if session.linkedPadding { session.paddingAfter = value }
                                    }
                                ), range: 0...1))
                if !session.linkedPadding {
                    parameter(.init(title: "After speech", detail: nil, value: $session.paddingAfter, range: 0...1))
                }
            }
            parameter(.init(title: "Merge nearby pauses", detail: "Join pauses across brief quiet sounds. Detected speech stays separate. Set to zero to turn off.",
                            value: $session.minimumAudio, range: 0...0.5))
        }
        .disabled(session.isAuditioning || session.loading || session.windows.isEmpty || !session.suggestsPauses)
    }

    private struct Parameter {
        let title: String
        let detail: String?
        let value: Binding<Double>
        let range: ClosedRange<Double>
    }

    private func parameter(_ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(parameter.title).font(BlitzType.label)
                Spacer(minLength: 0)
                Text("\(parameter.value.wrappedValue, specifier: "%.2f") s")
                    .font(BlitzType.body.monospacedDigit())
                    .foregroundStyle(BlitzUI.supportingText)
            }
            Slider(value: Binding(get: { parameter.value.wrappedValue }, set: { value in
                parameter.value.wrappedValue = value
                session.customized = true
                session.recalculate()
            }), in: parameter.range, step: 0.05)
                .controlSize(.small)
                .accessibilityLabel(parameter.title)
                .accessibilityValue(String(format: "%.2f seconds", parameter.value.wrappedValue))
            if let detail = parameter.detail {
                Text(detail)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
