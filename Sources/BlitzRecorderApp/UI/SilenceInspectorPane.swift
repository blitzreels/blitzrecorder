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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    detection
                    pacing
                }
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                result
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                BlitzInspectorDisclosure(configuration: .init(
                    title: "Fine-tune",
                    detail: session.customized ? "Custom" : session.automaticThreshold ? "Automatic" : "Manual",
                    isExpanded: $showsTuning,
                    content: { tuning }
                ))
                if let error = session.error {
                    Text(error).font(.system(size: 13)).foregroundStyle(BlitzUI.recordRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .buttonStyle(BlitzButtonStyle(.secondary))
        .controlSize(.large)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SilenceTime.label(session.metrics.outputDuration))
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .fixedSize()
                Spacer(minLength: 8)
                if session.metrics.removedDuration > 0 {
                    Text("−\(SilenceTime.label(session.metrics.removedDuration))")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(BlitzUI.mint)
                        .fixedSize()
                }
            }
            Text(summaryCaption)
                .font(.system(size: 13))
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("After removal, \(SilenceTime.label(session.metrics.outputDuration)), from \(SilenceTime.label(session.duration)), \(session.metrics.pauseCount) pauses, save \(SilenceTime.label(session.metrics.removedDuration))")
    }

    private var summaryCaption: String {
        let pauses = session.metrics.pauseCount == 1 ? "1 pause" : "\(session.metrics.pauseCount) pauses"
        return "from \(SilenceTime.label(session.duration)) · \(pauses)"
    }

    private var detection: some View {
        Toggle(isOn: Binding(
            get: { session.suggestsPauses }, set: { session.setSuggestionsEnabled($0) }
        )) {
            Text("Find pauses")
                .font(.system(size: 14, weight: .semibold))
        }
        .toggleStyle(.blitzSwitch)
        .accessibilityLabel("Find pauses")
        .help("Suggest automatic silence cuts. Turning this off keeps your manual selections.")
        .disabled(session.loading || session.windows.isEmpty)
    }

    private var selectedPacing: SilencePacing? {
        session.suggestsPauses && !session.customized
            ? SilencePacing(rawValue: Int(session.intensity.rounded())) : nil
    }

    private var pacing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(
                value: Binding(
                    get: { session.suggestsPauses ? max(1, session.intensity) : 1 },
                    set: { value in
                        if let pace = SilencePacing(rawValue: Int(value.rounded())) {
                            session.selectPacing(pace)
                        }
                    }
                ),
                in: Double(SilencePacing.natural.rawValue)...Double(SilencePacing.rapid.rawValue),
                step: 1
            )
            .controlSize(.regular)
            .tint(BlitzUI.mint)
            .accessibilityLabel("Pause removal")
            .accessibilityValue(selectedPacing?.title ?? "Custom")
            .help("How aggressively pauses are removed between phrases.")
            .disabled(!session.suggestsPauses)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(SilencePacing.allCases.enumerated()), id: \.element.rawValue) { index, pace in
                    let alignment: Alignment =
                        index == 0 ? .leading
                        : index == SilencePacing.allCases.count - 1 ? .trailing : .center
                    Button {
                        session.selectPacing(pace)
                    } label: {
                        Text(pace.title)
                            .font(.system(size: 12, weight: selectedPacing == pace ? .semibold : .regular))
                            .foregroundStyle(selectedPacing == pace ? BlitzUI.primaryText : BlitzUI.supportingText)
                            .frame(maxWidth: .infinity, alignment: alignment)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pace.title)
                    .accessibilityAddTraits(selectedPacing == pace ? .isSelected : [])
                    .pointingHandCursor()
                    .disabled(!session.suggestsPauses)
                }
            }
            Text(!session.suggestsPauses ? "Automatic cuts are off. Manual selections are kept."
                 : session.customized ? "Using your custom pause and speech spacing."
                 : (selectedPacing ?? .natural).detail)
                .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(session.loading || session.windows.isEmpty)
    }

    private var tuning: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio source: \(session.sourceName)")
                .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Automatic threshold", isOn: $session.automaticThreshold)
                    .toggleStyle(.blitzSwitch)
                    .onChange(of: session.automaticThreshold) { _, _ in session.changeThresholdMode() }
                if session.automaticThreshold {
                    Text("Audio below \(Int(session.threshold)) dB is treated as silence.")
                        .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
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
                    Text("Speech spacing").font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    Toggle("Link", isOn: $session.linkedPadding)
                        .toggleStyle(.blitzCheckbox)
                        .accessibilityLabel("Link silence padding")
                }
                parameter(.init(title: "Before", detail: nil, value: $session.paddingBefore, range: 0...1))
                if !session.linkedPadding {
                    parameter(.init(title: "After", detail: nil, value: $session.paddingAfter, range: 0...1))
                }
            }
            .help("Keep space before and after speech. Link applies the same amount to both sides.")
            parameter(.init(title: "Ignore short sounds", detail: "Remove audio spikes shorter than this. Zero keeps them.",
                            value: $session.minimumAudio, range: 0...0.5))
        }
        .disabled(session.loading || !session.suggestsPauses)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.loading {
                summary
            }
            if session.loading || session.calculating || session.preparingPreview {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(session.loading ? "Analyzing audio…"
                         : session.calculating ? "Updating cuts…" : "Preparing preview…")
                        .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                }
            }
            SilencePreviewToggle(configuration: .init(session: session, presentation: .inspector))
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
                Text(parameter.title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Text("\(parameter.value.wrappedValue, specifier: "%.2f") s")
                    .font(.system(size: 13, design: .monospaced))
            }
            Slider(value: Binding(get: { parameter.value.wrappedValue }, set: { value in
                parameter.value.wrappedValue = value
                session.customized = true
                session.recalculate()
            }), in: parameter.range, step: 0.05)
                .accessibilityLabel(parameter.title)
        }
        .help(parameter.detail ?? parameter.title)
    }
}
