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

    /// Wide players carry their transport inside the frame; narrow (portrait) ones keep it underneath.
    private var overlaysTransport: Bool { playerLayout.videoSize.width >= 520 }

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
        VStack(spacing: 12) {
            videoSurface
                .overlay(alignment: .bottom) {
                    if overlaysTransport, isPlaybackReady {
                        transport
                            .padding(.leading, 7)
                            .padding(.trailing, 10)
                            .frame(height: 48)
                            .blitzGlass(cornerRadius: BlitzUI.surfaceRadius - 2)
                            .padding(12)
                    }
                }
            if !overlaysTransport {
                transport.frame(width: playerLayout.transportWidth)
            }
        }
        .frame(width: playerLayout.transportWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project playback")
    }

    private var transport: some View {
        ProjectLibraryPlaybackControls(configuration: .init(
            controller: configuration.controller,
            waveformSamples: configuration.waveformSamples
        ))
        .opacity(isPlaybackReady ? 1 : 0)
        .disabled(!isPlaybackReady)
        .accessibilityHidden(!isPlaybackReady)
    }

    private var showsPoster: Bool {
        guard isPlaybackReady else { return true }
        return !ProjectLibraryPosterPolicy.hasVisibleVideo(.init(
            exportedPlayerIsReadyForDisplay: configuration.controller.filePlayer.map {
                readyForDisplayPlayer == ObjectIdentifier($0)
            }
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
                        cropDraft: nil
                    )
                    .allowsHitTesting(false)
                }
            }

            poster
                .opacity(showsPoster ? 1 : 0)
                .allowsHitTesting(false)

            if !isPlaybackReady {
                if configuration.fallbackThumbnail != nil, configuration.loadError == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .padding(8)
                        .background(.black.opacity(0.55), in: .circle)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .accessibilityLabel("Preparing playback")
                } else {
                    loadingStatus
                }
            }
        }
        .frame(width: playerLayout.videoSize.width, height: playerLayout.videoSize.height)
        .clipShape(.rect(cornerRadius: BlitzUI.surfaceRadius, style: .continuous))
        .overlay { BlitzEdgeHighlight(cornerRadius: BlitzUI.surfaceRadius) }
        .shadow(color: BlitzUI.deepShadow, radius: 16, y: 8)
    }

    @ViewBuilder
    private var poster: some View {
        if let fallbackThumbnail = configuration.fallbackThumbnail {
            Image(nsImage: fallbackThumbnail)
                .resizable()
                .scaledToFit()
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
                    .foregroundStyle(BlitzUI.onMediaText)

                Text(loadError)
                    .font(BlitzType.footnote)
                    .foregroundStyle(BlitzUI.onMediaSecondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text("Preparing playback")
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(BlitzUI.onMediaSecondaryText)
            }
        }
        .padding(16)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: BlitzUI.cardRadius))
    }

}

struct ProjectLibraryPosterRequest {
    let exportedPlayerIsReadyForDisplay: Bool?
}

enum ProjectLibraryPosterPolicy {
    static func hasVisibleVideo(_ request: ProjectLibraryPosterRequest) -> Bool {
        if let isReady = request.exportedPlayerIsReadyForDisplay {
            return isReady
        }
        return true
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
            playerLayer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
                                   "opacity": NSNull(), "contents": NSNull()]
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
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
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
    }
}
