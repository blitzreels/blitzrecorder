import SwiftUI

struct EditorTimelineTrackHeader<Accessory: View>: View {
    struct Configuration {
        let title: String
        let symbol: String
        let tint: Color
        let status: String?
        let height: CGFloat
        let isSelected: Bool
        let isInteractive: Bool
        let onSelect: (() -> Void)?
        @ViewBuilder let accessory: () -> Accessory
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 2) {
            if let onSelect = configuration.onSelect {
                Button(action: onSelect) {
                    label.frame(minHeight: max(0, configuration.height - 8))
                }
                .blitzButton(.quiet)
                .controlSize(.mini)
                .disabled(!configuration.isInteractive)
                .accessibilityLabel("Select \(configuration.title) track")
                .accessibilityValue(configuration.status ?? "")
                .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
                .help("Select the \(configuration.title) track")
            } else {
                label.padding(.horizontal, 8)
            }
            configuration.accessory()
        }
        .padding(.horizontal, 2)
        .frame(height: configuration.height)
        .background(configuration.isSelected ? BlitzUI.selectedFill : .clear,
                    in: .rect(cornerRadius: BlitzUI.controlRadius))
        .overlay(alignment: .leading) {
            if configuration.isSelected {
                Capsule().fill(BlitzUI.mint)
                    .frame(width: 2, height: min(20, configuration.height - 8))
                    .allowsHitTesting(false)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            BlitzSymbol(configuration: .init(name: configuration.symbol, size: 14))
                .foregroundStyle(configuration.status == nil ? configuration.tint : BlitzUI.secondaryText)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.title)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(configuration.status == nil ? BlitzUI.primaryText : BlitzUI.supportingText)
                    .lineLimit(1)
                if let status = configuration.status {
                    Text(status)
                        .font(BlitzType.footnote)
                        .foregroundStyle(BlitzUI.supportingText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }
}

struct EditorTimelineTrackToggle: View {
    struct Configuration {
        let title: String
        let isVideo: Bool
        let isOff: Bool
        let isInteractive: Bool
        let onToggle: () -> Void
    }

    let configuration: Configuration

    private var symbol: String {
        configuration.isVideo
            ? (configuration.isOff ? "eye.slash" : "eye")
            : (configuration.isOff ? "speaker.slash" : "speaker.wave.2")
    }

    private var verb: String {
        configuration.isVideo
            ? (configuration.isOff ? "Show" : "Hide")
            : (configuration.isOff ? "Unmute" : "Mute")
    }

    var body: some View {
        Button(action: configuration.onToggle) {
            Image(systemName: symbol)
                .frame(width: 14, height: 16)
        }
        .blitzButton(configuration.isOff ? .secondary : .quiet)
        .controlSize(.mini)
        .disabled(!configuration.isInteractive)
        .accessibilityLabel("\(verb) \(configuration.title)")
        .accessibilityValue(configuration.isOff ? (configuration.isVideo ? "Hidden" : "Muted") : "Included")
        .help("\(verb) \(configuration.title) throughout playback and the entire export")
    }
}
