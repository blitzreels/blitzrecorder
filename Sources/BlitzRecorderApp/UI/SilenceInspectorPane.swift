import SwiftUI

enum SilencePacing: Int, CaseIterable {
    case natural = 1
    case tight = 2
    case rapid = 3

    var title: String {
        switch self {
        case .natural: "Natural"
        case .tight: "Tight"
        case .rapid: "Rapid"
        }
    }

    var detail: String {
        switch self {
        case .natural: "Keep breathing room around speech."
        case .tight: "Shorten pauses for a quicker pace."
        case .rapid: "Keep speech close together."
        }
    }
}

struct SilenceInspectorPane: View {
    @Bindable var session: SilenceEditingSession
    @State private var showsTuning = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    pacing
                    Divider()
                    BlitzInspectorDisclosure(configuration: .init(
                        title: "Fine-tune detection",
                        detail: session.customized ? "Custom" : session.automaticThreshold ? "Automatic" : "Manual threshold",
                        isExpanded: $showsTuning,
                        content: { tuning }
                    ))
                    Label("Select a timeline section and press Delete to keep or remove it.", systemImage: "cursorarrow")
                        .font(.system(size: 11))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = session.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(BlitzUI.recordRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            Divider()
            footer.padding(14)
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
        VStack(alignment: .leading, spacing: 12) {
            BlitzInspectorHeading(configuration: .init(title: "After removal", detail: session.sourceName))
            if session.loading {
                Label("Finding pauses…", systemImage: "waveform")
                    .font(.system(size: 14, weight: .medium))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(SilenceTime.label(session.metrics.outputDuration))
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text("from \(SilenceTime.label(session.duration))")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text("\(session.metrics.pauseCount) pauses")
                    Spacer(minLength: 0)
                    Text("Save \(SilenceTime.label(session.metrics.removedDuration))")
                        .foregroundStyle(session.metrics.removedDuration > 0 ? BlitzUI.mint : BlitzUI.secondaryText)
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .opacity(session.calculating ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private var pacing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Find pauses", isOn: Binding(
                get: { session.suggestsPauses }, set: { session.setSuggestionsEnabled($0) }
            ))
            .toggleStyle(.blitzSwitch)
            .help("Suggest automatic silence cuts. Turning this off keeps your manual selections.")
            HStack(alignment: .top, spacing: 4) {
                ForEach(SilencePacing.allCases, id: \.self) { pace in
                    BlitzVisualChoice(configuration: .init(
                        title: pace.title, help: pace.detail,
                        isSelected: session.suggestsPauses && !session.customized && Int(session.intensity) == pace.rawValue,
                        action: { session.selectPacing(pace) },
                        preview: { SilencePacingPreview(pacing: pace) }
                    ))
                }
            }
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
            if session.loading || session.calculating || session.preparingPreview {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(session.loading ? "Analyzing audio…"
                         : session.calculating ? "Updating cuts…" : "Preparing preview…")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            SilencePreviewToggle(session: session)
            Text("Hear the result before applying.")
                .font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
            if !session.hasRemovedSilence || session.metrics.hasChanges {
                Button {
                    _ = session.apply()
                } label: {
                    Label(session.hasRemovedSilence ? "Update silence cuts" : "Apply silence cuts", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.accent)
                .disabled(!session.canApply)
                .help("Remove silence and close gaps on every track, in playback and export. Undo with ⌘Z.")
            }
            if session.hasRemovedSilence {
                Button { session.restoreSilence() } label: {
                    Text("Restore removed silence").frame(maxWidth: .infinity)
                }
                    .blitzButton(.secondary)
                    .disabled(session.loading || session.calculating || session.preparingPreview)
            }
            Text("All tracks stay in sync · ⌘Z to undo")
                .font(.system(size: 10)).foregroundStyle(BlitzUI.secondaryText)
                .frame(maxWidth: .infinity)
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

struct SilencePacingPreview: View {
    let pacing: SilencePacing

    var body: some View {
        Canvas { context, size in
            let gap = CGFloat(4 - pacing.rawValue) * size.width * 0.055
            let groupWidth = max(1, (size.width - gap * 2 - 8) / 3)
            for group in 0..<3 {
                for bar in 0..<7 {
                    let height = CGFloat([0.3, 0.6, 0.9, 0.5, 0.75, 0.4, 0.2][bar]) * size.height * 0.65
                    let x = 4 + CGFloat(group) * (groupWidth + gap) + CGFloat(bar) * groupWidth / 7
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: max(1.5, groupWidth / 10), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(BlitzUI.mint.opacity(0.8)))
                }
            }
        }
        .background(BlitzUI.scenePreviewFill)
        .accessibilityHidden(true)
    }
}
