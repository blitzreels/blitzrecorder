import SwiftUI

@MainActor
struct ProjectLibraryPlaybackControls: View {
    struct Configuration {
        let controller: EditorPlaybackController
        let waveformSamples: [Float]
    }

    let configuration: Configuration

    private var displayedDuration: Double {
        let output = configuration.controller.outputDuration
        return output > 0 ? output : configuration.controller.duration
    }

    private var displayedTime: Double {
        configuration.controller.nowPlayingTime
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                configuration.controller.togglePlayback()
            } label: {
                Image(systemName: configuration.controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(BlitzType.glyph(12))
                    .foregroundStyle(BlitzUI.inverseText)
                    .offset(x: configuration.controller.isPlaying ? 0 : 1.5)
                    .frame(width: 34, height: 34)
                    .background(BlitzUI.primaryText, in: .circle)
                    .shadow(color: BlitzUI.elevationShadow, radius: 6, y: 2)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(configuration.controller.isPlaying ? "Pause" : "Play")
            .help(configuration.controller.isPlaying ? "Pause" : "Play")

            timecode(displayedTime)

            ProjectPlaybackWaveform(
                samples: configuration.waveformSamples,
                currentTime: displayedTime,
                duration: displayedDuration,
                onScrub: { time in
                    configuration.controller.scrubToOutput(time)
                },
                onScrubEnd: configuration.controller.endScrub
            )
            .frame(height: 30)

            timecode(displayedDuration)

            BlitzSegmentedPicker(configuration: .init(
                title: "Playback speed",
                options: EditorPlaybackRate.allCases,
                selection: Binding(
                    get: { configuration.controller.playbackRate },
                    set: { configuration.controller.setPlaybackRate($0) }
                ),
                label: { $0.displayName }
            ))
            .controlSize(.mini)
            .fixedSize()
        }
    }

    private func timecode(_ time: Double) -> some View {
        BlitzTimecode(configuration: .init(time: time, duration: displayedDuration))
            .font(BlitzType.caption.monospaced())
            .monospacedDigit()
            .foregroundStyle(BlitzUI.supportingText)
            .fixedSize()
    }
}

struct ProjectPlaybackWaveform: View {
    @State private var hoverX: CGFloat?
    @State private var isDragging = false

    private struct SeekRequest {
        let x: CGFloat
        let width: CGFloat
    }

    let samples: [Float]
    let currentTime: Double
    let duration: Double
    let onScrub: (Double) -> Void
    let onScrubEnd: () -> Void

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let playedWidth = size.width * progress
                let midY = size.height / 2
                if samples.isEmpty {
                    let track = CGRect(x: 0, y: midY - 2, width: size.width, height: 4)
                    context.fill(Path(roundedRect: track, cornerRadius: 2), with: .color(BlitzUI.strongFill))
                    let played = CGRect(x: 0, y: midY - 2, width: playedWidth, height: 4)
                    context.fill(Path(roundedRect: played, cornerRadius: 2), with: .color(BlitzUI.accent))
                } else {
                    let slot = size.width / CGFloat(samples.count)
                    let barWidth = max(1, min(2.5, slot * 0.58))
                    let maxHeight = max(1, size.height - 4)
                    for (index, value) in samples.enumerated() {
                        let height = max(2, CGFloat(min(1, max(0, value))) * maxHeight)
                        let x = CGFloat(index) * slot + (slot - barWidth) / 2
                        let bar = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                        let color = bar.midX <= playedWidth ? BlitzUI.accent : BlitzUI.tertiaryText
                        context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(color))
                    }
                }

                if let hoverX, !isDragging {
                    let guide = CGRect(x: hoverX - 0.5, y: 2, width: 1, height: max(0, size.height - 4))
                    context.fill(Path(guide), with: .color(BlitzUI.tertiaryText))
                }

                if samples.isEmpty {
                    let diameter: CGFloat = hoverX != nil || isDragging ? 14 : 12
                    let headX = 7 + (size.width - 14) * progress
                    let knob = CGRect(x: headX - diameter / 2, y: midY - diameter / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: knob.insetBy(dx: -1, dy: -1)), with: .color(BlitzUI.panelBackground))
                    context.fill(Path(ellipseIn: knob), with: .color(BlitzUI.primaryText))
                } else {
                    let headX = min(max(playedWidth, 1), size.width - 1)
                    let head = CGRect(x: headX - 1, y: 0, width: 2, height: size.height)
                    context.fill(Path(roundedRect: head.insetBy(dx: -1, dy: -1), cornerRadius: 2), with: .color(BlitzUI.panelBackground))
                    context.fill(Path(roundedRect: head, cornerRadius: 1), with: .color(BlitzUI.primaryText))
                }
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverX = min(max(0, location.x), proxy.size.width)
                case .ended:
                    hoverX = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let hoverX, duration > 0 {
                    Text(timeLabel(time(.init(x: hoverX, width: proxy.size.width))))
                        .font(BlitzType.footnote.monospacedDigit())
                        .foregroundStyle(BlitzUI.primaryText)
                        .frame(width: 52, height: 20)
                        .background(BlitzUI.panelBackground, in: .rect(cornerRadius: 6, style: .continuous))
                        .offset(x: min(max(0, hoverX - 26), max(0, proxy.size.width - 52)), y: -26)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .blitzCursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        onScrub(time(.init(
                            x: value.location.x,
                            width: proxy.size.width
                        )))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrubEnd()
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(samples.isEmpty ? "Playback position" : "Playback waveform")
        .accessibilityValue(timeLabel(currentTime))
        .accessibilityAdjustableAction { direction in
            let step = max(1, duration / 100)
            switch direction {
            case .increment:
                onScrub(min(duration, currentTime + step))
                onScrubEnd()
            case .decrement:
                onScrub(max(0, currentTime - step))
                onScrubEnd()
            @unknown default:
                break
            }
        }
        .help("Click or drag to seek")
    }

    private func time(_ request: SeekRequest) -> Double {
        guard request.width > 0, duration > 0 else { return 0 }
        return min(1, max(0, request.x / request.width)) * duration
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        MediaTimecode.label(.init(time: time, duration: duration))
    }
}
