import SwiftUI

struct SilencePaneActions {
    let apply: () -> Void
    let restore: () -> Void
    let keepCurrent: () -> Void
    let setPreview: (Bool) -> Void
    let selectStrength: (SilenceStrength) -> Void
}

struct SilenceSummaryCard: View {
    let presentation: SilencePanePresentation
    let phaseStartedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            TimelineView(.periodic(from: phaseStartedAt, by: 1)) { context in
                headline(elapsed: context.date.timeIntervalSince(phaseStartedAt))
            }
            if let progress = presentation.phase.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(BlitzUI.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: presentation)
    }

    private var status: some View {
        HStack(spacing: 6) {
            switch presentation.phase {
            case .scanning, .analyzingSpeech:
                ProgressView().controlSize(.mini)
                Text(presentation.phase.statusTitle).foregroundStyle(BlitzUI.supportingText)
            case .applied:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(BlitzUI.accent)
                Text("Pauses cut").foregroundStyle(BlitzUI.supportingText)
            case .proposed:
                Image(systemName: BlitzSymbols.edit).foregroundStyle(BlitzUI.supportingText)
                Text(presentation.hasAppliedCuts ? "New settings, not applied yet" : "Preview, not applied yet")
                    .foregroundStyle(BlitzUI.supportingText)
            case .noPauses:
                Image(systemName: "waveform").foregroundStyle(BlitzUI.secondaryText)
                Text("No long pauses found").foregroundStyle(BlitzUI.supportingText)
            case .unavailable:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BlitzUI.warning)
                Text("No audio to scan").foregroundStyle(BlitzUI.supportingText)
            }
            Spacer(minLength: 0)
            if presentation.isUpdating && presentation.hasResult {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Updating cuts")
            }
        }
        .font(BlitzType.captionEmphasis)
        .frame(height: 16)
    }

    @ViewBuilder
    private func headline(elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch presentation.phase {
            case .scanning(let fraction):
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(SilencePaneType.display)
                    .contentTransition(.numericText())
                Text(presentation.progressLine(.init(elapsed: elapsed)))
                    .foregroundStyle(BlitzUI.supportingText)
            case .analyzingSpeech(_, let title):
                Text(title)
                    .font(SilencePaneType.displayText)
                Text(presentation.progressLine(.init(elapsed: elapsed)) + " · Words are never cut")
                    .foregroundStyle(BlitzUI.supportingText)
            case .unavailable(let message):
                Text("Nothing to scan")
                    .font(SilencePaneType.displayText)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            case .proposed, .applied, .noPauses:
                HStack(alignment: .firstTextBaseline) {
                    Text(ClockDuration.label(presentation.editedDuration))
                        .font(SilencePaneType.display)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    if presentation.removedDuration > 0 {
                        Text("−\(ClockDuration.label(presentation.removedDuration))")
                            .font(BlitzType.headline)
                            .foregroundStyle(BlitzUI.accent)
                            .contentTransition(.numericText())
                    }
                }
                Text(resultLine)
                    .foregroundStyle(BlitzUI.supportingText)
            }
        }
        .font(BlitzType.body)
        .foregroundStyle(BlitzUI.primaryText)
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
    }

    private var resultLine: String {
        let total = ClockDuration.label(presentation.originalDuration)
        guard presentation.pauseCount > 0 else { return "No long pauses in \(total)" }
        let pauses = presentation.pauseCount == 1 ? "1 pause" : "\(presentation.pauseCount) pauses"
        return presentation.phase == .applied ? "\(pauses) cut from \(total)" : "\(pauses) found in \(total)"
    }
}

enum SilencePaneType {
    static let display = Font.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit()
    static let displayText = Font.system(size: 20, weight: .semibold)
}

private extension SilencePanePresentation.Phase {
    var statusTitle: String {
        switch self {
        case .scanning: "Scanning audio"
        case .analyzingSpeech: "Analyzing speech"
        default: ""
        }
    }

    var progress: Double? {
        switch self {
        case .scanning(let fraction): fraction
        case .analyzingSpeech(let step, _): Double(step - 1) / 4 + 0.125
        default: nil
        }
    }
}

struct SilenceStrengthSection: View {
    let presentation: SilencePanePresentation
    let actions: SilencePaneActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlitzInspectorHeading(configuration: .init(title: "Strength", detail: presentation.strength == nil ? "Custom" : nil))
            BlitzSegmentedPicker(configuration: .init(
                title: "Silence removal strength",
                options: SilenceStrength.pickerCases.map(Optional.some),
                selection: Binding<SilenceStrength?>(
                    get: { presentation.strength },
                    set: { if let strength = $0 { actions.selectStrength(strength) } }
                ),
                label: { $0?.title ?? "Custom" }
            ))
            Text(presentation.strengthDetail)
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Right-click a pause on the timeline to keep it.")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.phase == .proposed, presentation.pauseCount > 0 {
                Toggle(isOn: Binding(get: { presentation.previewEnabled }, set: actions.setPreview)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play with pauses cut")
                            .font(BlitzType.label)
                        Text("Hear the result before you apply it.")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                .toggleStyle(.blitzSwitch)
                .padding(.top, 6)
            }
        }
        .disabled(!presentation.hasResult)
    }
}

struct SilenceFooterActions: View {
    let presentation: SilencePanePresentation
    let actions: SilencePaneActions

    var body: some View {
        VStack(spacing: 8) {
            if let warning = presentation.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if presentation.phase == .applied {
                Button(action: actions.restore) {
                    Label("Restore pauses", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.secondary)
                .controlSize(.large)
                .help("Put every cut pause back on the timeline")
                caption("Changes apply right away · ⌘Z to undo")
            } else {
                Button(action: actions.apply) {
                    Label(applyTitle, systemImage: BlitzSymbols.edit)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                }
                .blitzButton(.accent)
                .controlSize(.large)
                .disabled(!presentation.canApply)
                .help("Cut these pauses from the timeline and every export")
                if presentation.hasAppliedCuts {
                    Button(action: actions.keepCurrent) {
                        Text("Keep current cuts").frame(maxWidth: .infinity)
                    }
                    .blitzButton(.secondary)
                    .controlSize(.large)
                    .help("Go back to the pauses you already cut")
                }
                caption(applyCaption)
            }
        }
        .animation(.easeOut(duration: 0.15), value: presentation)
    }

    private var applyTitle: String {
        guard presentation.hasResult, presentation.pauseCount > 0 else {
            return presentation.hasAppliedCuts ? "Apply new settings" : "Cut pauses"
        }
        return presentation.pauseCount == 1 ? "Cut 1 pause" : "Cut \(presentation.pauseCount) pauses"
    }

    private var applyCaption: String {
        if presentation.isWorking { return "Ready when the scan finishes" }
        guard presentation.removedDuration > 0 else { return "⌘Z to undo" }
        return "Saves \(ClockDuration.label(presentation.removedDuration)) · ⌘Z to undo"
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(BlitzType.caption)
            .foregroundStyle(BlitzUI.secondaryText)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
    }
}
