import AppKit
import AVFoundation
import Foundation
import SwiftUI

struct ProjectLibraryPlayerSizeRequest {
    let contentSize: CGSize
    let maximumSize: CGSize
}

struct ProjectLibraryPlayerLayout {
    let videoSize: CGSize
    let transportWidth: CGFloat
}

struct ProjectLibraryOverviewSizeRequest {
    let viewportSize: CGSize
}

struct ProjectLibraryOverviewLayout {
    let contentWidth: CGFloat
    let playerMaximumSize: CGSize
}

enum ProjectLibraryOverviewSizing {
    static func layout(_ request: ProjectLibraryOverviewSizeRequest) -> ProjectLibraryOverviewLayout {
        let contentWidth = min(1_080, max(320, request.viewportSize.width - 68))
        let playerHeight = min(640, max(240, request.viewportSize.height - 150))
        return ProjectLibraryOverviewLayout(
            contentWidth: contentWidth,
            playerMaximumSize: CGSize(width: contentWidth, height: playerHeight)
        )
    }
}

enum ProjectLibraryPlayerSizing {
    static func layout(_ request: ProjectLibraryPlayerSizeRequest) -> ProjectLibraryPlayerLayout {
        guard request.contentSize.width > 0,
              request.contentSize.height > 0,
              request.maximumSize.width > 0,
              request.maximumSize.height > 0 else {
            return ProjectLibraryPlayerLayout(videoSize: .zero, transportWidth: 0)
        }
        let scale = min(
            request.maximumSize.width / request.contentSize.width,
            request.maximumSize.height / request.contentSize.height
        )
        return ProjectLibraryPlayerLayout(
            videoSize: CGSize(
                width: request.contentSize.width * scale,
                height: request.contentSize.height * scale
            ),
            transportWidth: request.maximumSize.width
        )
    }
}

struct ProjectLibraryPlaybackReloadRequest {
    let selectedProjectPath: String
    let loadedProjectPath: String?
    let hasActivePlayback: Bool
}

enum ProjectLibraryPlaybackReloadPolicy {
    static func shouldReload(_ request: ProjectLibraryPlaybackReloadRequest) -> Bool {
        !request.hasActivePlayback || request.selectedProjectPath != request.loadedProjectPath
    }
}

@MainActor
struct ProjectLibraryPlayerSurface: View {
    struct Configuration {
        let controller: EditorPlaybackController
        let isCurrentProject: Bool
        let fallbackThumbnail: NSImage?
        let waveformSamples: [Float]
        let loadError: String?
        let maximumSize: CGSize
    }

    let configuration: Configuration
    @State private var readyForDisplayPlayer: ObjectIdentifier?

    private var isPlaybackReady: Bool {
        configuration.isCurrentProject && configuration.controller.isReady
    }

    private var playerLayout: ProjectLibraryPlayerLayout {
        let contentSize: CGSize
        if configuration.controller.renderSize.width > 0,
           configuration.controller.renderSize.height > 0 {
            contentSize = configuration.controller.renderSize
        } else if let fallbackThumbnail = configuration.fallbackThumbnail,
                  fallbackThumbnail.size.width > 0,
                  fallbackThumbnail.size.height > 0 {
            contentSize = fallbackThumbnail.size
        } else {
            contentSize = CGSize(width: 16, height: 9)
        }
        return ProjectLibraryPlayerSizing.layout(.init(
            contentSize: contentSize,
            maximumSize: configuration.maximumSize
        ))
    }

    var body: some View {
        VStack(spacing: 10) {
            videoSurface

            ProjectLibraryPlaybackControls(configuration: .init(
                controller: configuration.controller,
                waveformSamples: configuration.waveformSamples
            ))
            .frame(width: playerLayout.transportWidth)
            .opacity(isPlaybackReady ? 1 : 0)
            .disabled(!isPlaybackReady)
            .accessibilityHidden(!isPlaybackReady)
        }
        .frame(width: playerLayout.transportWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project playback")
    }

    private var showsPoster: Bool {
        guard isPlaybackReady else { return true }
        return !ProjectLibraryPosterPolicy.hasVisibleVideo(.init(
            exportedPlayerIsReadyForDisplay: configuration.controller.filePlayer.map {
                readyForDisplayPlayer == ObjectIdentifier($0)
            },
            isPlaying: configuration.controller.isPlaying,
            currentTime: configuration.controller.nowPlayingTime
        ))
    }

    private var videoSurface: some View {
        ZStack {
            Color.black

            if isPlaybackReady {
                if let player = configuration.controller.filePlayer {
                    ProjectLibraryExportedPlayer(configuration: .init(
                        player: player,
                        onReadyForDisplay: { isReady in
                            readyForDisplayPlayer = isReady ? ObjectIdentifier(player) : nil
                        }
                    ))
                    .allowsHitTesting(false)
                } else {
                    EditorCompositedPlayer(
                        controller: configuration.controller,
                        renderSize: configuration.controller.renderSize,
                        previewSceneRevision: configuration.controller.previewSceneRevision,
                        cameraCropEditingScene: nil
                    )
                    .allowsHitTesting(false)
                }
            }

            poster
                .opacity(showsPoster ? 1 : 0)
                .allowsHitTesting(false)

            if !isPlaybackReady {
                loadingStatus
            }
        }
        .frame(width: playerLayout.videoSize.width, height: playerLayout.videoSize.height)
        .clipShape(.rect(cornerRadius: BlitzUI.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                .strokeBorder(BlitzUI.separator, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let fallbackThumbnail = configuration.fallbackThumbnail {
            Image(nsImage: fallbackThumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: playerLayout.videoSize.width, height: playerLayout.videoSize.height)
                .clipped()
                .accessibilityHidden(true)
        }
    }

    private var loadingStatus: some View {
        VStack(spacing: 10) {
            if let loadError = configuration.loadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.glyph(22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.warning)

                Text("Playback unavailable")
                    .font(BlitzType.section)
                    .foregroundStyle(BlitzUI.primaryText)

                Text(loadError)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text("Preparing playback")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.supportingText)
            }
        }
        .padding(16)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: BlitzUI.cardRadius))
    }

}

struct ProjectLibraryPosterRequest {
    let exportedPlayerIsReadyForDisplay: Bool?
    let isPlaying: Bool
    let currentTime: Double
}

enum ProjectLibraryPosterPolicy {
    static func hasVisibleVideo(_ request: ProjectLibraryPosterRequest) -> Bool {
        if let isReady = request.exportedPlayerIsReadyForDisplay {
            return isReady
        }
        return request.isPlaying || request.currentTime > 0
    }
}

private struct ProjectLibraryExportedPlayer: NSViewRepresentable {
    struct Configuration {
        let player: AVPlayer
        let onReadyForDisplay: (Bool) -> Void
    }

    let configuration: Configuration

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.onReadyForDisplay = configuration.onReadyForDisplay
        view.attach(configuration.player)
        return view
    }

    func updateNSView(_ nsView: PlayerView, context: Context) {
        nsView.onReadyForDisplay = configuration.onReadyForDisplay
        nsView.attach(configuration.player)
    }

    static func dismantleNSView(_ nsView: PlayerView, coordinator: ()) {
        nsView.detach()
    }

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()
        var onReadyForDisplay: ((Bool) -> Void)?
        private var readyObservation: NSKeyValueObservation?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func attach(_ player: AVPlayer) {
            guard playerLayer.player !== player || readyObservation == nil else { return }
            playerLayer.player = player
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let isReady = layer.isReadyForDisplay
                DispatchQueue.main.async {
                    guard let self, self.playerLayer.player === player else { return }
                    self.onReadyForDisplay?(isReady)
                }
            }
        }

        func detach() {
            readyObservation = nil
            playerLayer.player = nil
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}

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
                    .foregroundStyle(BlitzUI.primaryText)
                    .offset(x: configuration.controller.isPlaying ? 0 : 1)
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(BlitzButtonStyle(.secondary))
            .keyboardShortcut(.space, modifiers: [])
            .pointingHandCursor()
            .accessibilityLabel(configuration.controller.isPlaying ? "Pause" : "Play")
            .help(configuration.controller.isPlaying ? "Pause" : "Play")

            BlitzTimecode(configuration: .init(
                time: displayedTime, duration: displayedDuration
            ))
                .font(BlitzType.caption.monospaced())
                .monospacedDigit()
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize()

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

            BlitzTimecode(configuration: .init(
                time: displayedDuration, duration: displayedDuration
            ))
                .font(BlitzType.caption.monospaced())
                .monospacedDigit()
                .foregroundStyle(BlitzUI.supportingText)
                .fixedSize()

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

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


}

private struct ProjectPlaybackWaveform: View {
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
                    context.fill(Path(roundedRect: played, cornerRadius: 2), with: .color(BlitzUI.mint))
                } else {
                    let slot = size.width / CGFloat(samples.count)
                    let barWidth = max(1, min(2.5, slot * 0.58))
                    let maxHeight = max(1, size.height - 4)
                    for (index, value) in samples.enumerated() {
                        let height = max(2, CGFloat(min(1, max(0, value))) * maxHeight)
                        let x = CGFloat(index) * slot + (slot - barWidth) / 2
                        let bar = CGRect(x: x, y: midY - height / 2, width: barWidth, height: height)
                        let color = bar.midX <= playedWidth ? BlitzUI.mint : BlitzUI.tertiaryText
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

struct ProjectLibraryActionButtonConfiguration {
    enum Tone: Equatable {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let tone: Tone
    let isLoading: Bool
    let action: () -> Void
}

struct ProjectLibraryActionButton: View {
    let configuration: ProjectLibraryActionButtonConfiguration

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 7) {
                if configuration.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    BlitzSymbol(configuration: .init(name: configuration.systemImage, size: 16))
                }

                Text(configuration.title)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(BlitzButtonStyle(configuration.tone == .primary ? .accent : .secondary))
        .disabled(configuration.isLoading)
        .pointingHandCursor()
    }
}

struct ProjectLibraryIconActionButtonConfiguration {
    enum Tone: Equatable {
        case secondary
        case destructive
    }

    let title: String
    let systemImage: String
    let tone: Tone
    let action: () -> Void
}

struct ProjectLibraryIconActionButton: View {
    let configuration: ProjectLibraryIconActionButtonConfiguration

    var body: some View {
        Button(
            role: configuration.tone == .destructive ? .destructive : nil,
            action: configuration.action
        ) {
            BlitzSymbol(configuration: .init(name: configuration.systemImage, size: 16))
        }
        .buttonStyle(BlitzButtonStyle(.secondary))
        .pointingHandCursor()
        .help(configuration.title)
        .accessibilityLabel(configuration.title)
    }
}
