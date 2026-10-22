import SwiftUI

struct RecordingHUDMeter: View {
    let levels: TrackLevels
    let isActive: Bool

    var body: some View {
        let recent = Array(levels.levels.suffix(5))
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(isActive ? BlitzUI.accent : BlitzUI.tertiaryText)
                    .frame(width: 3, height: max(3, CGFloat(min(1, level)) * 16))
            }
        }
        .frame(width: 23, height: 16)
        .animation(.linear(duration: 0.08), value: recent)
        .accessibilityLabel("Microphone level")
    }
}

struct RecordingHUDIconButton: View {
    struct Configuration {
        let symbol: String
        let fill: Color
        let help: String
        let isEnabled: Bool
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    var body: some View {
        Button(action: configuration.action) {
            glyph
                .foregroundStyle(BlitzUI.primaryText)
                .frame(width: 30, height: 30)
                .background(configuration.fill, in: .circle)
                .background(isHovering ? BlitzUI.selectedFill : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(!configuration.isEnabled)
        .onHover { isHovering = $0 }
        .help(configuration.help)
        .accessibilityLabel(configuration.help)
    }

    /// Stop and pause are drawn, not SF Symbols, whose glyphs sit up to a point off the button's center.
    @ViewBuilder private var glyph: some View {
        switch configuration.symbol {
        case "stop.fill":
            RoundedRectangle(cornerRadius: 2, style: .circular).frame(width: 10, height: 10)
        case "pause.fill":
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1, style: .circular).frame(width: 3, height: 10)
                RoundedRectangle(cornerRadius: 1, style: .circular).frame(width: 3, height: 10)
            }
        default:
            Image(systemName: configuration.symbol).font(BlitzType.symbol(11))
        }
    }
}

struct RecordingHUDDot: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BlitzStatusDot(tone: .recording, diameter: 8)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
            }
            .accessibilityHidden(true)
    }
}
