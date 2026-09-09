import SwiftUI

enum EditorPlaybackPosition {
    struct ParseRequest {
        let text: String
        let duration: Double
    }

    static func display(_ time: Double) -> String {
        let value = time.isFinite ? min(9_999_999, max(0, time)) : 0
        let hundredths = Int((value * 100).rounded())
        let minutes = hundredths / 6_000
        let seconds = hundredths / 100 % 60
        let fraction = hundredths % 100
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d.%02d", minutes / 60, minutes % 60, seconds, fraction)
        }
        return String(format: "%02d:%02d.%02d", minutes, seconds, fraction)
    }

    static func parse(_ request: ParseRequest) -> Double? {
        guard request.duration.isFinite, request.duration > 0 else { return nil }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let components = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        var time: Double = 0
        for (index, component) in components.enumerated() {
            guard !component.isEmpty,
                component.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                let value = Double(component), value.isFinite, value >= 0,
                index == components.count - 1 || !component.contains("."),
                index == 0 || value < 60
            else { return nil }
            time = time * 60 + value
        }
        return time <= request.duration ? time : nil
    }
}

struct EditorPlaybackControls: View {
    struct Configuration {
        let time: Double
        let duration: Double
        let isPlaying: Bool
        let isEnabled: Bool
        let rate: EditorPlaybackRate
        let onSeek: (Double) -> Void
        let onTogglePlayback: () -> Void
        let onPreviousScene: () -> Void
        let onNextScene: () -> Void
        let onRateChange: (EditorPlaybackRate) -> Void
    }

    let configuration: Configuration
    @State private var showsPosition = false
    @State private var positionText = ""
    @FocusState private var isPositionFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button {
                    configuration.onSeek(0)
                } label: {
                    BlitzSymbol(configuration: .init(name: "backward.end.fill", size: 16))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
                .accessibilityLabel("Go to start")
                .help("Go to the start of the recording (Home)")
                .pointingHandCursor()

                Button(action: configuration.onTogglePlayback) {
                    BlitzSymbol(
                        configuration: .init(name: configuration.isPlaying ? "pause.fill" : "play.fill", size: 20)
                    )
                    .offset(x: configuration.isPlaying ? 0 : 1)
                    .frame(width: 28, height: 36)
                }
                .blitzProminentGlassButton()
                .accessibilityLabel(configuration.isPlaying ? "Pause" : "Play")
                .help(configuration.isPlaying ? "Pause (Space)" : "Play (Space or L)")
                .pointingHandCursor()

                Button {
                    configuration.onSeek(configuration.duration)
                } label: {
                    BlitzSymbol(configuration: .init(name: "forward.end.fill", size: 16))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
                .accessibilityLabel("Go to end")
                .help("Go to the end of the recording (End)")
                .pointingHandCursor()
            }
            position
            speed
        }
        .disabled(!configuration.isEnabled)
        .contextMenu {
            Button("Previous scene", systemImage: "backward.end") { configuration.onPreviousScene() }
            Button("Next scene", systemImage: "forward.end") { configuration.onNextScene() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback controls")
    }

    private var position: some View {
        Button {
            positionText = EditorPlaybackPosition.display(configuration.time)
            showsPosition = true
        } label: {
            HStack(spacing: 7) {
                Text(EditorPlaybackPosition.display(configuration.time).dropLast(3))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BlitzUI.primaryText)
                Text("/")
                    .foregroundStyle(BlitzUI.secondaryText.opacity(0.5))
                Text(EditorPlaybackPosition.display(configuration.duration).dropLast(3))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .monospacedDigit()
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 44)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: showsPosition))
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(EditorPlaybackPosition.display(configuration.time)) of \(EditorPlaybackPosition.display(configuration.duration))"
        )
        .help("Click to jump to a time")
        .pointingHandCursor()
        .popover(isPresented: $showsPosition, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                BlitzUI.sectionLabel("Jump to time", icon: "clock")
                HStack(spacing: 8) {
                    TextField("08:07.25", text: $positionText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .focused($isPositionFocused)
                        .onSubmit(jumpToPosition)
                        .accessibilityLabel("Time to jump to")
                    Button("Go", action: jumpToPosition)
                        .blitzProminentGlassButton()
                        .disabled(parsedPosition == nil)
                }
                Text(
                    parsedPosition == nil
                        ? "Enter a time within this recording." : "Minutes:seconds, or seconds with decimals."
                )
                .font(.system(size: 11))
                .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(16)
            .frame(width: 300)
            .background(BlitzUI.panelBackground)
            .controlSize(.regular)
            .onAppear { isPositionFocused = true }
        }
    }

    private var parsedPosition: Double? {
        EditorPlaybackPosition.parse(.init(text: positionText, duration: configuration.duration))
    }

    private func jumpToPosition() {
        guard let time = parsedPosition else { return }
        configuration.onSeek(time)
        showsPosition = false
    }

    private var speed: some View {
        BlitzGlassMenu(
            entries: EditorPlaybackRate.allCases.map { rate in
                .item(
                    BlitzMenuItem(
                        title: rate.displayName,
                        systemImage: "speedometer",
                        isSelected: configuration.rate == rate,
                        action: { configuration.onRateChange(rate) }
                    ))
            }, menuWidth: 160
        ) {
            HStack(spacing: 7) {
                Text(configuration.rate.displayName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                BlitzSymbol(configuration: .init(name: "chevron.down", size: 9))
            }
            .foregroundStyle(BlitzUI.primaryText)
            .frame(width: 58, height: 36)
            .blitzSelectedSurface(isSelected: false, cornerRadius: BlitzUI.controlRadius)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(configuration.rate.displayName)
        .pointingHandCursor()
        .help("Playback speed (L)")
    }
}
