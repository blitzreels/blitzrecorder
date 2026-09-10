import SwiftUI

struct NowPlayingMenuView: View {
    @Bindable var playback: NowPlayingController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playback.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(playback.isPlaying ? "Playing" : "Paused")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 22) {
                Button {
                    playback.perform(.skip(-10))
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .accessibilityLabel("Skip back 10 seconds")
                .help("Skip back 10 seconds")
                .pointingHandCursor()

                Button {
                    playback.perform(.toggle)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 38, height: 32)
                }
                .accessibilityLabel(playback.isPlaying ? "Pause playback" : "Resume playback")
                .pointingHandCursor()

                Button {
                    playback.perform(.skip(10))
                } label: {
                    Image(systemName: "goforward.10")
                }
                .accessibilityLabel("Skip forward 10 seconds")
                .help("Skip forward 10 seconds")
                .pointingHandCursor()
            }
            .font(.system(size: 18))
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)

            Slider(value: Binding(
                get: { playback.elapsedTime },
                set: { playback.perform(.seek($0)) }
            ), in: 0...max(playback.duration, 0.01))
            .accessibilityLabel("Playback position")

            HStack {
                Text(time(playback.elapsedTime))
                Spacer()
                Text(time(playback.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
