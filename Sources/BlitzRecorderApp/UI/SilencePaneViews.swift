import SwiftUI

struct SilencePaneActions {
    let apply: () -> Void
    let restore: () -> Void
    let setPreview: (Bool) -> Void
    let selectStrength: (SilenceStrength) -> Void
}

struct SilenceSummaryCard: View {
    let presentation: SilencePanePresentation
    let phaseStartedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            status
            TimelineView(.periodic(from: phaseStartedAt, by: 1)) { context in
                headline(elapsed: context.date.timeIntervalSince(phaseStartedAt))
            }
            if presentation.phase.showsTimeline {
                timeline
                stats
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .animation(.easeOut(duration: 0.2), value: presentation)
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            SilenceTakeStrip(presentation: presentation)
                .frame(height: 30)
            HStack {
                Text("0:00")
                Spacer(minLength: 0)
                Text(ClockDuration.label(presentation.originalDuration))
            }
            .font(BlitzType.footnote)
            .foregroundStyle(BlitzUI.tertiaryText)
            .monospacedDigit()
            .opacity(presentation.originalDuration > 0 ? 1 : 0)
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            switch presentation.phase {
            case .scanning, .analyzingSpeech:
                ProgressView().controlSize(.mini)
                Text(presentation.phase.statusTitle).foregroundStyle(BlitzUI.supportingText)
            case .applied:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(BlitzUI.mint)
                Text("Pauses cut").foregroundStyle(BlitzUI.supportingText)
            case .proposed:
                Image(systemName: "scissors").foregroundStyle(BlitzUI.supportingText)
                Text(presentation.hasAppliedCuts ? "New settings, not applied yet" : "Preview, not applied yet")
                    .foregroundStyle(BlitzUI.supportingText)
            case .noPauses:
                Image(systemName: "waveform").foregroundStyle(BlitzUI.secondaryText)
                Text("No long pauses found").foregroundStyle(BlitzUI.supportingText)
            case .unavailable:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BlitzUI.warning)
                Text("Audio unavailable").foregroundStyle(BlitzUI.supportingText)
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
                Text(message)
                    .foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            case .proposed, .applied, .noPauses:
                Text(ClockDuration.label(presentation.editedDuration))
                    .font(SilencePaneType.display)
                    .contentTransition(.numericText())
                Text(presentation.removedDuration > 0
                     ? "Down from \(ClockDuration.label(presentation.originalDuration))"
                     : "Same length as the recording")
                    .foregroundStyle(BlitzUI.supportingText)
            }
        }
        .font(BlitzType.body)
        .foregroundStyle(BlitzUI.primaryText)
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(.init(value: presentation.hasResult ? "\(presentation.pauseCount)" : "–",
                       label: presentation.pauseCount == 1 ? "Pause" : "Pauses", tint: BlitzUI.primaryText))
            stat(.init(value: savedValue,
                       label: "Time saved",
                       tint: presentation.hasResult && presentation.removedDuration > 0 ? BlitzUI.mint : BlitzUI.primaryText))
            stat(.init(value: presentation.hasResult ? "\(presentation.shorterPercent)%" : "–",
                       label: "Shorter", tint: BlitzUI.primaryText))
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(BlitzUI.separator).frame(height: 1) }
    }

    private var savedValue: String {
        guard presentation.hasResult else { return "–" }
        guard presentation.removedDuration > 0 else { return "0:00" }
        return "−\(ClockDuration.label(presentation.removedDuration))"
    }

    private struct Stat {
        let value: String
        let label: String
        let tint: Color
    }

    private func stat(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.value)
                .font(BlitzType.headline)
                .foregroundStyle(stat.tint)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(stat.label)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

    var showsTimeline: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

struct SilenceTakeStrip: View {
    let presentation: SilencePanePresentation

    var body: some View {
        Canvas { context, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6, style: .continuous)
            context.fill(track, with: .color(BlitzUI.quietFill))
            switch presentation.phase {
            case .scanning(let fraction):
                fill(.init(context: context, size: size, fraction: fraction))
            case .analyzingSpeech(let step, _):
                fill(.init(context: context, size: size, fraction: Double(step - 1) / 4 + 0.125))
            case .unavailable:
                break
            case .proposed, .applied, .noPauses:
                drawSpeech(.init(context: context, size: size))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Recording timeline")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        presentation.hasResult
            ? "\(presentation.pauseCount) pauses marked for cutting"
            : presentation.phase.statusTitle
    }

    private struct FillRequest {
        let context: GraphicsContext
        let size: CGSize
        let fraction: Double
    }

    private func fill(_ request: FillRequest) {
        let width = max(0, min(1, request.fraction)) * request.size.width
        guard width > 0 else { return }
        let rect = CGRect(x: 0, y: 0, width: width, height: request.size.height)
        request.context.fill(Path(roundedRect: rect, cornerRadius: 6, style: .continuous),
                             with: .color(BlitzUI.mint.opacity(0.85)))
    }

    private struct DrawRequest {
        let context: GraphicsContext
        let size: CGSize
    }

    private func drawSpeech(_ request: DrawRequest) {
        let radius: (CGRect) -> CGFloat = { min(1, $0.width / 2) }
        for bar in Self.bars(.init(columns: presentation.columns, size: request.size)) {
            request.context.fill(Path(roundedRect: bar.rect, cornerRadius: radius(bar.rect)),
                                 with: .color(BlitzUI.primaryText.opacity(0.14)))
            let keptHeight = bar.rect.height * CGFloat(bar.kept)
            guard keptHeight >= 1 else { continue }
            let kept = CGRect(x: bar.rect.minX, y: bar.rect.midY - keptHeight / 2, width: bar.rect.width, height: keptHeight)
            request.context.fill(Path(roundedRect: kept, cornerRadius: radius(kept)),
                                 with: .color(BlitzUI.primaryText.opacity(0.78)))
        }
    }

    struct BarsRequest {
        let columns: [SilenceStripColumn]
        let size: CGSize
    }

    struct Bar: Equatable {
        let rect: CGRect
        let kept: Double
    }

    static func bars(_ request: BarsRequest) -> [Bar] {
        guard !request.columns.isEmpty, request.size.width > 0 else { return [] }
        let inset: CGFloat = 5
        let pitch = (request.size.width - inset * 2) / CGFloat(request.columns.count)
        let width = max(1, pitch * 0.6)
        let height = request.size.height - inset * 2
        return request.columns.enumerated().map { index, column in
            let barHeight = max(2, height * CGFloat(column.level))
            return Bar(rect: CGRect(x: inset + CGFloat(index) * pitch + (pitch - width) / 2,
                                    y: inset + (height - barHeight) / 2, width: width, height: barHeight),
                       kept: column.kept)
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
                options: SilenceStrength.allCases.map(Optional.some),
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
            switch presentation.phase {
            case .applied:
                Button(action: actions.restore) {
                    Label("Restore pauses", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.secondary)
                .controlSize(.large)
                .help("Put every cut pause back on the timeline")
                caption("Brings back \(ClockDuration.label(presentation.removedDuration)) · ⌘Z to undo")
            default:
                Button(action: actions.apply) {
                    Label(applyTitle, systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                }
                .blitzButton(.accent)
                .controlSize(.large)
                .disabled(!presentation.canApply)
                .help("Cut these pauses from the timeline and every export")
                caption(applyCaption)
            }
        }
        .animation(.easeOut(duration: 0.2), value: presentation)
    }

    private var applyTitle: String {
        if presentation.hasAppliedCuts { return "Update cuts" }
        guard presentation.hasResult, presentation.pauseCount > 0 else { return "Cut pauses" }
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
