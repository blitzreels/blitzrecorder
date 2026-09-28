import SwiftUI

enum SilencePacing: Int, CaseIterable {
    case natural = 1
    case tight = 2
    case rapid = 3

    var title: String {
        switch self {
        case .natural: "Gentle"
        case .tight: "Balanced"
        case .rapid: "Strong"
        }
    }

    var detail: String {
        switch self {
        case .natural: "Keep breathing room around speech."
        case .tight: "Shorten silences for a quicker pace."
        case .rapid: "Leave very little space between phrases."
        }
    }
}

struct SilenceInspectorPane: View {
    @Bindable var session: SilenceEditingSession
    @State private var showsTuning = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    detection
                    summary
                    BlitzInspectorDisclosure(configuration: .init(
                        title: "Fine-tune",
                        detail: session.customized ? "Custom" : nil,
                        isExpanded: $showsTuning,
                        content: { tuning }
                    ))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            if session.hasChanges || session.skipSilence || session.hasRemovedSilence || session.error != nil || session.waitingForTranscript {
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .buttonStyle(BlitzButtonStyle(.secondary))
        .controlSize(.regular)
        .tint(BlitzUI.mint)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Silence removal")
                .font(.system(size: 17, weight: .semibold))
            Text("Shorten gaps between spoken phrases.")
                .font(.system(size: 12))
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var detection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Detect silence", isOn: Binding(
                get: { session.suggestsPauses }, set: { session.setSuggestionsEnabled($0) }
            ))
            .toggleStyle(.blitzSwitch)
            .help("Suggest automatic silence cuts. Turning this off keeps your manual selections.")
            BlitzSegmentedPicker(configuration: .init(
                title: "Silence removal strength",
                options: SilencePacing.allCases.map(Optional.some),
                selection: Binding<SilencePacing?>(
                    get: { selectedPacing },
                    set: { if let pace = $0 { session.selectPacing(pace) } }
                ),
                label: { $0?.title ?? "Custom" }
            ))
            .disabled(!session.suggestsPauses)
            Text(!session.suggestsPauses ? "Detection is off. Manual selections are kept."
                 : session.customized ? "Custom silence length and speech padding."
                 : (selectedPacing ?? .natural).detail)
                .font(.system(size: 12))
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(session.isAuditioning || session.loading || session.windows.isEmpty)
    }

    private var selectedPacing: SilencePacing? {
        session.suggestsPauses && !session.customized
            ? SilencePacing(rawValue: Int(session.intensity.rounded())) : nil
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.loading {
                status("Analyzing audio…")
                Text("Finding the quiet moments in your recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.supportingText)
            } else if session.windows.isEmpty {
                Text("Audio unavailable")
                    .font(.system(size: 13, weight: .medium))
                Text("Silence detection needs a readable audio track.")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.supportingText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.hasChanges ? "After removal" : "Edited duration")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BlitzUI.supportingText)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(SilenceTime.label(session.metrics.outputDuration))
                            .font(.system(size: 30, weight: .medium, design: .rounded))
                            .foregroundStyle(BlitzUI.primaryText)
                            .fixedSize()
                        Spacer(minLength: 0)
                        if session.metrics.removedDuration > 0 {
                            Text("−\(SilenceTime.label(session.metrics.removedDuration))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(BlitzUI.mint)
                                .fixedSize()
                        }
                    }
                    Text("Original · \(SilenceTime.label(session.duration))")
                        .font(.system(size: 12))
                        .foregroundStyle(BlitzUI.supportingText)
                }
                .monospacedDigit()
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                if session.waitingForTranscript {
                    status("Finishing speech analysis…")
                    Text("Apply becomes available when all pauses are ready.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.supportingText)
                } else if session.calculating || session.preparingPreview {
                    status(session.calculating ? "Updating silences…" : "Preparing preview…")
                } else {
                    Label {
                        Text(silenceCountLabel)
                    } icon: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BlitzUI.recordRed)
                            .frame(width: 8, height: 8)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var silenceCountLabel: String {
        guard session.metrics.pauseCount > 0 else { return "No silences selected" }
        let count = session.metrics.pauseCount == 1 ? "1 silence" : "\(session.metrics.pauseCount) silences"
        return session.hasRemovedSilence && !session.hasChanges ? "\(count) removed" : count
    }

    private func status(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(BlitzUI.supportingText)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = session.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.recordRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.windows.isEmpty {
                HStack(spacing: 8) {
                    Button("Listen before") { session.audition(false) }
                    Button("Listen after") { session.audition(true) }
                }
                .blitzButton(.secondary)
                .controlSize(.small)
                .disabled(session.loading || session.calculating || session.waitingForTranscript || session.isAuditioning)
                if session.isAuditioning {
                    HStack {
                        status("Playing a short comparison…")
                        Spacer(minLength: 0)
                        Button("Stop") { session.stopAudition() }
                            .blitzButton(.quiet)
                            .controlSize(.small)
                    }
                }
            }
            SilencePreviewToggle(session: session)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(BlitzUI.projectLibraryBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(BlitzUI.separator).frame(height: 1)
        }
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
                    onReset: { session.threshold = -42; session.recalculate() }
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
            parameter(.init(title: "Ignore short sounds", detail: "Skip brief audio spikes. Set to zero to keep them.",
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
                Text(parameter.title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text("\(parameter.value.wrappedValue, specifier: "%.2f") s")
                    .font(.system(size: 12, design: .monospaced))
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
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
