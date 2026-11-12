import SwiftUI

enum SilencePacing: Int, CaseIterable {
    case natural = 1
    case tight = 2
    case rapid = 3
}

struct SilenceInspectorPane: View {
    @Bindable var session: SilenceEditingSession
    @State private var showsAdvanced = false
    @State private var phaseStartedAt = Date()

    var body: some View {
        let presentation = session.presentation
        let actions = SilencePaneActions(
            apply: { _ = session.apply() },
            restore: session.restoreSilence,
            keepCurrent: session.keepCurrentCuts,
            setPreview: session.setPreviewEnabled,
            selectStrength: session.selectStrength
        )
        EditorInspectorPane(configuration: .init(
            title: "Silence",
            detail: "Cut the long pauses between phrases.",
            showsFooter: presentation.phase.showsFooter,
            content: {
                VStack(alignment: .leading, spacing: EditorInspectorMetrics.sectionSpacing) {
                    SilenceSummaryCard(presentation: presentation, phaseStartedAt: phaseStartedAt)
                    if presentation.hasResult {
                        SilenceStrengthSection(presentation: presentation, actions: actions)
                        if session.suggestsPauses && !session.windows.isEmpty { fineTune }
                    }
                }
            },
            footer: { SilenceFooterActions(presentation: presentation, actions: actions) }
        ))
        .onChange(of: presentation.phase.kind) { phaseStartedAt = Date() }
    }

    private var fineTune: some View {
        VStack(alignment: .leading, spacing: 16) {
            BlitzInspectorHeading(configuration: .init(title: "Fine-tune", detail: session.customized ? "Custom" : nil))
            quietLevel
            parameter(.init(title: "Shortest pause", detail: nil,
                            value: $session.minimumDuration, range: SilenceRemovalSettings.minimumDurationRange, step: 0.05))
            parameter(.init(title: "Space around words", detail: nil,
                            value: Binding(
                                get: { session.paddingBefore },
                                set: { value in
                                    session.paddingBefore = value
                                    session.paddingAfter = value
                                    session.linkedPadding = true
                                }
                            ), range: 0...1, step: 0.05))
            BlitzInspectorDisclosure(configuration: .init(
                title: "Advanced",
                detail: nil,
                isExpanded: $showsAdvanced,
                content: { advanced }
            ))
        }
        .disabled(session.loading)
    }

    private var quietLevel: some View {
        VStack(alignment: .leading, spacing: 4) {
            BlitzInspectorSlider(configuration: .init(
                title: "Quiet level",
                value: Binding(get: { session.threshold }, set: session.setThreshold),
                range: SilenceRemovalSettings.thresholdRange, step: 1,
                valueLabel: "\(Int(session.threshold.rounded())) dB",
                onEditingChanged: { _ in },
                onReset: session.useAutomaticThreshold
            ))
            .help("Sound quieter than this level counts as a pause.")
            HStack(spacing: 8) {
                Text(session.automaticThreshold ? "Automatic · drag right to cut more" : "Drag right to cut more")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !session.automaticThreshold {
                    Button("Automatic", action: session.useAutomaticThreshold)
                        .blitzButton(.quiet)
                        .controlSize(.small)
                        .help("Let the app pick the level from \(session.sourceName.lowercased())")
                }
            }
            .frame(minHeight: 24)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Same space before and after words", isOn: Binding(
                get: { session.linkedPadding },
                set: { linked in
                    session.linkedPadding = linked
                    if linked { session.paddingAfter = session.paddingBefore }
                    session.customized = true
                    session.recalculate()
                }
            ))
                .toggleStyle(.blitzSwitch)
            if !session.linkedPadding {
                parameter(.init(title: "Before words", detail: nil, value: $session.paddingBefore, range: 0...1, step: 0.05))
                parameter(.init(title: "After words", detail: nil, value: $session.paddingAfter, range: 0...1, step: 0.05))
            }
            parameter(.init(title: "Ignore short noises",
                            detail: "A click or breath this short doesn't break a pause.",
                            value: $session.minimumAudio, range: 0...0.5, step: 0.05))
        }
    }

    private struct Parameter {
        let title: String
        let detail: String?
        let value: Binding<Double>
        let range: ClosedRange<Double>
        let step: Double
    }

    private func parameter(_ parameter: Parameter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BlitzInspectorSlider(configuration: .init(
                title: parameter.title,
                value: Binding(get: { parameter.value.wrappedValue }, set: { value in
                    parameter.value.wrappedValue = value
                    session.customized = true
                    session.recalculate()
                }),
                range: parameter.range,
                step: parameter.step,
                valueLabel: Self.seconds(parameter.value.wrappedValue),
                onEditingChanged: { _ in },
                onReset: {
                    session.selectPacing(SilencePacing(rawValue: Int(session.intensity.rounded())) ?? .tight)
                }
            ))
            .accessibilityValue(Self.seconds(parameter.value.wrappedValue))
            if let detail = parameter.detail {
                Text(detail)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func seconds(_ value: Double) -> String {
        guard value > 0.001 else { return "Off" }
        let rounded = (value * 100).rounded() / 100
        return rounded.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }
}
