import SwiftUI

/// A time value with − / + steps that can also be typed (12, 1:05, 1:05.5).
struct BlitzTimeStepper: View {
    struct Configuration {
        let title: String
        let value: Double
        let range: ClosedRange<Double>
        let step: Double
        let onCommit: (Double) -> Void
    }

    let configuration: Configuration
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepButton(symbol: "minus", delta: -1)
            TextField("m:ss", text: $text)
                .textFieldStyle(.plain)
                .font(BlitzType.label.monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .focused($isFocused)
                .onSubmit(commitText)
                .accessibilityLabel(configuration.title)
            stepButton(symbol: "plus", delta: 1)
        }
        .frame(height: 28)
        .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
        .onAppear(perform: refresh)
        .onChange(of: configuration.value) { _, _ in if !isFocused { refresh() } }
        .onChange(of: isFocused) { _, focused in if !focused { commitText() } }
    }

    private func stepButton(symbol: String, delta: Double) -> some View {
        let next = clamped(((configuration.value / configuration.step).rounded() + delta) * configuration.step)
        return Button { configuration.onCommit(next) } label: {
            Image(systemName: symbol).font(BlitzType.glyph(11)).frame(width: 26, height: 28).contentShape(.rect)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
        .disabled(next == configuration.value)
        .accessibilityLabel(delta < 0 ? "Less" : "More")
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, configuration.range.lowerBound), configuration.range.upperBound)
    }

    private func refresh() {
        text = BlitzTimeStepper.label(configuration.value)
    }

    private func commitText() {
        guard let value = EditorPlaybackPosition.parse(.init(text: text, duration: .greatestFiniteMagnitude)) else {
            refresh()
            return
        }
        let next = clamped(value)
        if abs(next - configuration.value) > 0.01 { configuration.onCommit(next) }
        text = BlitzTimeStepper.label(next)
    }

    static func label(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        let whole = tenths / 10
        let base = String(format: "%d:%02d", whole / 60, whole % 60)
        return tenths % 10 == 0 ? base : base + ".\(tenths % 10)"
    }
}

/// "Starts at" and "Lasts" rows for anything shown for part of the recording.
/// Moving the start keeps the length; times are in the original recording.
struct BlitzTimeRangeEditor: View {
    struct Configuration {
        let range: EditorTimeRange
        let duration: Double
        let playhead: Double
        let minimumLength: Double
        let onChange: (EditorTimeRange) -> Void
    }

    let configuration: Configuration

    var body: some View {
        let range = configuration.range
        let untilEnd = range.end >= configuration.duration - 0.05
        VStack(alignment: .leading, spacing: 10) {
            row(.init(
                title: "Starts at",
                stepper: .init(title: "Starts at", value: range.start,
                               range: 0...max(0, configuration.duration - configuration.minimumLength), step: 1,
                               onCommit: { setStart($0) }),
                action: .init(title: "Playhead", systemImage: "arrow.down.to.line",
                              help: "Start at the current playhead position", isEnabled: true,
                              run: { setStart(configuration.playhead) })
            ))
            row(.init(
                title: "Lasts",
                stepper: .init(title: "Lasts", value: range.duration,
                               range: configuration.minimumLength...max(configuration.minimumLength,
                                                                        configuration.duration - range.start),
                               step: 1, onCommit: { setLength($0) }),
                action: .init(title: "Until the end", systemImage: "arrow.right.to.line",
                              help: "Keep it until the end of the recording", isEnabled: !untilEnd,
                              run: { setLength(configuration.duration - range.start) })
            ))
        }
    }

    private struct Action {
        let title: String
        let systemImage: String
        let help: String
        let isEnabled: Bool
        let run: () -> Void
    }

    private struct Row {
        let title: String
        let stepper: BlitzTimeStepper.Configuration
        let action: Action
    }

    private func row(_ row: Row) -> some View {
        EditorInspectorRow(configuration: .init(title: row.title) {
            BlitzTimeStepper(configuration: row.stepper)
            Button(action: row.action.run) { Label(row.action.title, systemImage: row.action.systemImage) }
                .blitzButton(.quiet).controlSize(.small)
                .disabled(!row.action.isEnabled)
                .help(row.action.help)
            Spacer(minLength: 0)
        })
    }

    private func setStart(_ time: Double) {
        let length = configuration.range.duration
        let start = min(max(0, time), max(0, configuration.duration - configuration.minimumLength))
        configuration.onChange(.init(start: start, end: min(configuration.duration, start + length)))
    }

    private func setLength(_ length: Double) {
        let start = configuration.range.start
        configuration.onChange(.init(
            start: start, end: min(configuration.duration, start + max(configuration.minimumLength, length))))
    }
}
