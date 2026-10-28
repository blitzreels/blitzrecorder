import SwiftUI

/// What the timeline needs to run a multicam project's camera lanes like a switcher.
struct EditorTimelineMulticam {
    let program: MulticamProgram
    /// The camera whose sound is being prepared, while it is.
    let soundSwitch: String?
    let onCut: (MulticamShot) -> Void
    let onUseSound: (String) -> Void
}

/// A multicam camera lane's switches: show this camera from the playhead, and play or mute its sound. Only this
/// view reads the playhead, so playback redraws two buttons instead of the whole timeline.
struct EditorTimelineAngleControls: View {
    struct Configuration {
        let angle: MulticamProgram.Angle
        let playback: EditorPlaybackController
        /// The sound track is muted, so even the playing camera is silent.
        let isSoundMuted: Bool
        let isSwitchingSound: Bool
        let isInteractive: Bool
        let onCut: () -> Void
        let onSound: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        let angle = configuration.angle
        let isLive = angle.isLive(at: configuration.playback.currentTime)
        let isPlaying = angle.isSound && !configuration.isSoundMuted
        HStack(spacing: 2) {
            Button(action: configuration.onCut) {
                HStack(spacing: 3) {
                    Image(systemName: BlitzSymbols.camera).symbolVariant(isLive ? .fill : .none)
                    Text("\(angle.key)").font(BlitzType.footnote.monospacedDigit())
                }
                .foregroundStyle(isLive ? BlitzUI.accent : BlitzUI.secondaryText)
                .frame(height: 16)
            }
            .blitzButton(isLive ? .secondary : .quiet)
            .controlSize(.mini)
            .accessibilityLabel("Show \(angle.title)")
            .accessibilityValue(isLive ? "On screen" : "Off screen")
            .help(isLive ? "\(angle.title) is on screen at the playhead. Press \(angle.key) to show it alone."
                : "Show \(angle.title) from the playhead. Press \(angle.key).")
            Button(action: configuration.onSound) {
                Group {
                    if configuration.isSwitchingSound {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: soundSymbol(isPlaying: isPlaying))
                            .symbolVariant(isPlaying ? .fill : .none)
                            .foregroundStyle(isPlaying ? BlitzUI.accent : BlitzUI.secondaryText)
                    }
                }
                .frame(width: 14, height: 16)
            }
            .blitzButton(isPlaying ? .secondary : .quiet)
            .controlSize(.mini)
            .accessibilityLabel(soundLabel(isPlaying: isPlaying))
            .accessibilityValue(isPlaying ? "Playing" : "Silent")
            .help(soundLabel(isPlaying: isPlaying))
        }
        .disabled(!configuration.isInteractive)
    }

    private func soundSymbol(isPlaying: Bool) -> String {
        if isPlaying { return BlitzSymbols.systemAudio }
        return configuration.angle.isSound ? "speaker.slash" : "speaker"
    }

    private func soundLabel(isPlaying: Bool) -> String {
        let title = configuration.angle.title
        if isPlaying { return "Mute \(title)'s sound" }
        return configuration.angle.isSound ? "Unmute \(title)'s sound" : "Play \(title)'s sound instead"
    }
}

/// Shades the parts of a multicam camera lane where that camera is off screen and underlines where it is live, so
/// the lanes read like a switcher's program line. Draws only the visible stretch of the timeline.
struct EditorTimelineLiveShade: View {
    struct Configuration {
        let liveRanges: [Range<Double>]
        let projection: EditorTimelineProjection
        let duration: Double
        let pixelsPerSecond: CGFloat
        let viewport: EditorTimelineViewport
    }

    let configuration: Configuration

    var body: some View {
        let shade = configuration
        Canvas { context, size in
            func x(_ time: Double) -> CGFloat {
                CGFloat(shade.projection.displayTime(time)) * shade.pixelsPerSecond - shade.viewport.lowerBound
            }
            func fill(_ range: Range<Double>, _ rows: (y: CGFloat, height: CGFloat), _ color: Color) {
                let start = x(range.lowerBound)
                let end = x(range.upperBound)
                guard end > start, end >= 0, start <= size.width else { return }
                context.fill(Path(CGRect(x: start, y: rows.y, width: end - start, height: rows.height)), with: .color(color))
            }
            var offScreenStart = 0.0
            for range in shade.liveRanges {
                if range.lowerBound > offScreenStart {
                    fill(offScreenStart..<range.lowerBound, (0, size.height), BlitzUI.panelBackground.opacity(0.62))
                }
                fill(range, (size.height - 3, 3), BlitzUI.accent)
                offScreenStart = max(offScreenStart, range.upperBound)
            }
            if shade.duration > offScreenStart {
                fill(offScreenStart..<shade.duration, (0, size.height), BlitzUI.panelBackground.opacity(0.62))
            }
        }
        .frame(width: max(1, shade.viewport.width))
        .offset(x: shade.viewport.lowerBound)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
