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
        case .tight: "Shorten pauses for a quicker pace."
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
                    detection
                    pacing
                    Divider()
                    BlitzInspectorDisclosure(configuration: .init(
                        title: "Fine-tune detection",
                        detail: session.customized ? "Custom" : session.automaticThreshold ? "Automatic" : "Manual threshold",
                        isExpanded: $showsTuning,
                        content: { tuning }
                    ))
                    Divider()
                    if session.hasRemovedSilence {
                        Button("Restore removed silence") { session.restoreSilence() }
                            .blitzButton(.secondary)
                            .disabled(session.loading || session.calculating || session.preparingPreview)
                    }
                    if let error = session.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(BlitzUI.recordRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .buttonStyle(BlitzButtonStyle(.secondary))
        .tint(BlitzUI.mint)
        .onChange(of: session.paddingBefore) { _, value in
            if session.linkedPadding { session.paddingAfter = value }
        }
        .onChange(of: session.paddingAfter) { _, value in
            if session.linkedPadding { session.paddingBefore = value }
        }
        .onChange(of: session.linkedPadding) { _, linked in
            if linked {
                session.paddingAfter = session.paddingBefore
                session.recalculate()
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 8) {
            if session.loading {
                Label("Finding pauses…", systemImage: "waveform")
                    .font(.system(size: 12, weight: .medium))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("After removal")
                        .font(.system(size: 10))
                        .foregroundStyle(BlitzUI.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(SilenceTime.label(session.duration))
                            .font(.system(size: 11))
                            .foregroundStyle(BlitzUI.secondaryText)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(BlitzUI.secondaryText)
                        Text(SilenceTime.label(session.metrics.outputDuration))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                    }
                    .monospacedDigit()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(session.metrics.pauseCount) pauses")
                    Text("Save \(SilenceTime.label(session.metrics.removedDuration))")
                        .foregroundStyle(session.metrics.removedDuration > 0 ? BlitzUI.mint : BlitzUI.secondaryText)
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .opacity(session.calculating ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.loading ? "Finding pauses"
            : "After removal, \(SilenceTime.label(session.metrics.outputDuration)), from \(SilenceTime.label(session.duration)), \(session.metrics.pauseCount) pauses, save \(SilenceTime.label(session.metrics.removedDuration))")
    }

    private var detection: some View {
        Toggle(isOn: Binding(
            get: { session.suggestsPauses }, set: { session.setSuggestionsEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Find pauses")
                    .font(.system(size: 12, weight: .semibold))
                Text("Detect quiet gaps in your audio.")
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .toggleStyle(.blitzSwitch)
        .help("Suggest automatic silence cuts. Turning this off keeps your manual selections.")
        .disabled(session.loading || session.windows.isEmpty)
    }

    private var pacing: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzInspectorHeading(configuration: .init(title: "Pause removal", detail: session.sourceName))
            BlitzSegmentedPicker(configuration: .init(
                title: "Pause removal strength",
                options: SilencePacing.allCases.map(Optional.some),
                selection: Binding<SilencePacing?>(
                    get: {
                        session.suggestsPauses && !session.customized
                            ? SilencePacing(rawValue: Int(session.intensity)) : nil
                    },
                    set: { if let pace = $0 { session.selectPacing(pace) } }
                ),
                label: { $0?.title ?? "" }
            ))
            Text(!session.suggestsPauses ? "Automatic cuts are off. Manual selections are kept."
                 : session.customized ? "Using your custom pause and speech spacing."
                 : (SilencePacing(rawValue: Int(session.intensity)) ?? .natural).detail)
                .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(session.loading || session.windows.isEmpty)
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Automatic threshold", isOn: $session.automaticThreshold)
                    .toggleStyle(.blitzSwitch)
                    .onChange(of: session.automaticThreshold) { _, _ in session.changeThresholdMode() }
                if session.automaticThreshold {
                    Text("Audio below \(Int(session.threshold)) dB is treated as silence.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                } else {
                    BlitzInspectorSlider(configuration: .init(
                        title: "Threshold", value: $session.threshold, range: -70 ... -15, step: 1,
                        valueLabel: "\(Int(session.threshold)) dB",
                        onEditingChanged: { _ in },
                        onReset: { session.threshold = -42 }
                    ))
                    .onChange(of: session.threshold) { _, _ in session.recalculate() }
                }
            }
            parameter(.init(title: "Minimum pause", detail: "Remove pauses longer than this.",
                            value: $session.minimumDuration, range: 0.1...3))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Room around speech").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Toggle("Link", isOn: $session.linkedPadding)
                        .toggleStyle(.blitzCheckbox).controlSize(.small)
                        .accessibilityLabel("Link silence padding")
                }
                parameter(.init(title: "Before", detail: nil, value: $session.paddingBefore, range: 0...1))
                if !session.linkedPadding {
                    parameter(.init(title: "After", detail: nil, value: $session.paddingAfter, range: 0...1))
                }
                if session.linkedPadding {
                    Text("The same space is kept before and after speech.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            parameter(.init(title: "Ignore short sounds", detail: "Remove audio spikes shorter than this. Zero keeps them.",
                            value: $session.minimumAudio, range: 0...0.5))
        }
        .disabled(session.loading || !session.suggestsPauses)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            if session.loading || session.calculating || session.preparingPreview {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(session.loading ? "Analyzing audio…"
                         : session.calculating ? "Updating cuts…" : "Preparing preview…")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            SilencePreviewToggle(session: session)
        }
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
                Text(parameter.title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Text("\(parameter.value.wrappedValue, specifier: "%.2f") s")
                    .font(.system(size: 11, design: .monospaced))
            }
            Slider(value: Binding(get: { parameter.value.wrappedValue }, set: { value in
                parameter.value.wrappedValue = value
                session.customized = true
                session.recalculate()
            }), in: parameter.range, step: 0.05)
                .accessibilityLabel(parameter.title)
            if let detail = parameter.detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
