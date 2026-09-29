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
        var liveTime: (() -> Double)?
        let duration: Double
        let isPlaying: Bool
        let isEnabled: Bool
        let rate: EditorPlaybackRate
        let onSeek: (Double) -> Void
        let onTogglePlayback: () -> Void
        let onRateChange: (EditorPlaybackRate) -> Void
    }

    let configuration: Configuration
    @State private var showsPosition = false
    @State private var positionText = ""
    @FocusState private var isPositionFocused: Bool

    private var displayedTime: Double {
        if configuration.isPlaying, let liveTime = configuration.liveTime {
            return liveTime()
        }
        return configuration.time
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                transportButton(.init(symbol: "backward.end.fill", title: "Go to start",
                                      help: "Go to the start of the recording (Home)",
                                      action: { configuration.onSeek(0) }))
                Button(action: configuration.onTogglePlayback) {
                    Image(systemName: configuration.isPlaying ? "pause.fill" : "play.fill")
                        .font(BlitzType.glyph(13))
                        .foregroundStyle(.black.opacity(0.88))
                        .offset(x: configuration.isPlaying ? 0 : 1)
                        .frame(width: 32, height: 32)
                        .background(BlitzUI.primaryText, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(BlitzPressButtonStyle())
                .accessibilityLabel(configuration.isPlaying ? "Pause" : "Play")
                .help(configuration.isPlaying ? "Pause (Space)" : "Play (Space or L)")
                transportButton(.init(symbol: "forward.end.fill", title: "Go to end",
                                      help: "Go to the end of the recording (End)",
                                      action: { configuration.onSeek(configuration.duration) }))
            }
            .padding(3)
            .background(BlitzUI.quietFill, in: Capsule())
            position
            speed
        }
        .disabled(!configuration.isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback controls")
    }

    private struct Transport {
        let symbol: String
        let title: String
        let help: String
        let action: () -> Void
    }

    private func transportButton(_ transport: Transport) -> some View {
        Button(action: transport.action) {
            Image(systemName: transport.symbol)
                .font(BlitzType.glyph(12))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
        .clipShape(Circle())
        .accessibilityLabel(transport.title)
        .help(transport.help)
        .pointingHandCursor()
    }

    private var position: some View {
        Button {
            positionText = EditorPlaybackPosition.display(displayedTime)
            showsPosition = true
        } label: {
            Group {
                if configuration.isPlaying, configuration.liveTime != nil {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { _ in
                        timecodeStack(displayedTime)
                    }
                } else {
                    timecodeStack(displayedTime)
                }
            }
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: showsPosition))
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(EditorPlaybackPosition.display(displayedTime)) of \(EditorPlaybackPosition.display(configuration.duration))"
        )
        .help("Click to jump to a time")
        .pointingHandCursor()
        .popover(isPresented: $showsPosition, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                BlitzUI.sectionLabel("Jump to time")
                HStack(spacing: 8) {
                    TextField("08:07.25", text: $positionText)
                        .textFieldStyle(.roundedBorder)
                        .font(BlitzType.headline.monospaced())
                        .focused($isPositionFocused)
                        .onSubmit(jumpToPosition)
                        .accessibilityLabel("Time to jump to")
                    Button("Go", action: jumpToPosition)
                        .blitzButton(.accent)
                        .disabled(parsedPosition == nil)
                }
                Text(
                    parsedPosition == nil
                        ? "Enter a time within this recording." : "Minutes:seconds, or seconds with decimals."
                )
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(16)
            .frame(width: 300)
            .background(BlitzUI.panelBackground)
            .controlSize(.regular)
            .onAppear { isPositionFocused = true }
        }
    }

    private func timecodeStack(_ time: Double) -> some View {
        HStack(spacing: 7) {
            BlitzTimecode(configuration: .init(time: time, duration: configuration.duration))
                .font(BlitzType.section.monospacedDigit())
                .foregroundStyle(BlitzUI.primaryText)
            Text("/")
                .foregroundStyle(BlitzUI.secondaryText.opacity(0.5))
            BlitzTimecode(configuration: .init(time: configuration.duration, duration: configuration.duration))
                .font(BlitzType.label.monospacedDigit())
                .foregroundStyle(BlitzUI.secondaryText)
        }
        .monospacedDigit()
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 32)
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
        BlitzGlassMenu(entries: EditorPlaybackRate.allCases.map { rate in
            .item(.init(title: rate.displayName, systemImage: nil, isSelected: rate == configuration.rate,
                        action: { configuration.onRateChange(rate) }))
        }, menuWidth: 120) {
            HStack(spacing: 5) {
                Text(configuration.rate.displayName)
                    .font(BlitzType.label.monospacedDigit())
                    .frame(minWidth: 30, alignment: .leading)
                BlitzMenuChevron()
            }
            .foregroundStyle(BlitzUI.primaryText)
            .padding(.horizontal, 10)
            .frame(height: BlitzControlMetrics.height(.small))
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(configuration.rate.displayName)
        .help("Playback speed (L to speed up)")
    }
}
