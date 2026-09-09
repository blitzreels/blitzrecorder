import SwiftUI

struct BlitzPlaybackVolumeControl: View {
    struct Configuration {
        let volume: Binding<Double>
        let sliderWidth: CGFloat
        let onToggleMute: () -> Void
    }

    let configuration: Configuration

    private var percentage: String {
        "\(Int((configuration.volume.wrappedValue * 100).rounded()))%"
    }

    private var symbolName: String {
        let volume = configuration.volume.wrappedValue
        return volume == 0 ? "speaker.slash" : (volume < 0.5 ? "speaker.wave.1" : "speaker.wave.2")
    }

    var body: some View {
        HStack(spacing: 4) {
            BlitzToolbarButton(
                configuration: .init(
                    title: configuration.volume.wrappedValue == 0 ? "Unmute" : "Mute",
                    symbolName: symbolName,
                    showsTitle: false,
                    action: configuration.onToggleMute
                )
            )
            .help(configuration.volume.wrappedValue == 0 ? "Restore listening volume" : "Mute preview playback")
            Slider(value: configuration.volume, in: 0...1)
                .tint(BlitzUI.mint)
                .controlSize(.small)
                .frame(width: configuration.sliderWidth)
                .accessibilityLabel("Playback volume")
                .accessibilityValue(percentage)
                .help("Listening volume for preview playback. Export audio is unchanged.")
            Text(percentage)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(BlitzUI.secondaryText)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback volume")
    }
}
