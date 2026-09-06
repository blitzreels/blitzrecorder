import AppKit
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

enum ProjectSpeechWaveform {
    struct Request {
        let segments: [RecordingTranscript.Segment]
        let duration: Double
        let bucketCount: Int
    }

    static func samples(_ request: Request) -> [Float] {
        guard request.duration > 0, request.bucketCount > 0 else {
            return []
        }

        let bucketDuration = request.duration / Double(request.bucketCount)
        var samples = [Float](repeating: 0, count: request.bucketCount)
        for segment in request.segments {
            let start = min(request.duration, max(0, segment.startTime))
            let end = min(request.duration, max(start, segment.endTime))
            let segmentDuration = end - start
            guard segmentDuration > 0 else { continue }

            let wordCount = segment.text.split(whereSeparator: \.isWhitespace).count
            let wordsPerSecond = Double(wordCount) / segmentDuration
            let confidence = min(1, max(0.55, Double(segment.confidence)))
            let intensity = min(1, 0.38 + wordsPerSecond * 0.20) * confidence
            let firstBucket = min(
                request.bucketCount - 1,
                max(0, Int(start / bucketDuration))
            )
            let lastBucket = min(
                request.bucketCount - 1,
                max(firstBucket, Int(end / bucketDuration))
            )

            for index in firstBucket...lastBucket {
                let bucketStart = Double(index) * bucketDuration
                let bucketEnd = bucketStart + bucketDuration
                let overlap = max(
                    0,
                    min(end, bucketEnd) - max(start, bucketStart)
                )
                let coverage = min(1, overlap / bucketDuration)
                let value = Float(sqrt(coverage) * intensity)
                samples[index] = max(samples[index], value)
            }
        }
        return samples
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

            if isPlaybackReady {
                ProjectLibraryPlaybackControls(configuration: .init(
                    controller: configuration.controller,
                    waveformSamples: configuration.waveformSamples
                ))
                .frame(width: playerLayout.transportWidth)
            }
        }
        .frame(width: playerLayout.transportWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project playback")
    }

    private var videoSurface: some View {
        ZStack {
            Color.black

            fallback
                .opacity(isPlaybackReady ? 0 : 1)

            if isPlaybackReady {
                EditorCompositedPlayer(
                    controller: configuration.controller,
                    renderSize: configuration.controller.renderSize,
                    previewSceneRevision: configuration.controller.previewSceneRevision,
                    cameraCropEditingScene: nil
                )
                .allowsHitTesting(false)
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
    private var fallback: some View {
        if let fallbackThumbnail = configuration.fallbackThumbnail {
            Image(nsImage: fallbackThumbnail)
                .resizable()
                .scaledToFill()
                .overlay {
                    Color.black.opacity(0.34)
                }
        }

        VStack(spacing: 10) {
            if let loadError = configuration.loadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlitzUI.warning)

                Text("Playback unavailable")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))

                Text(loadError)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)

                Text("Preparing playback")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(16)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: 12))
    }

}

@MainActor
struct ProjectLibraryPlaybackControls: View {
    struct Configuration {
        let controller: EditorPlaybackController
        let waveformSamples: [Float]
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 10) {
            Button {
                configuration.controller.togglePlayback()
            } label: {
                Image(systemName: configuration.controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BlitzUI.primaryText)
                    .offset(x: configuration.controller.isPlaying ? 0 : 1)
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(BlitzControlButtonStyle(isProminent: false))
            .keyboardShortcut(.space, modifiers: [])
            .pointingHandCursor()
            .accessibilityLabel(configuration.controller.isPlaying ? "Pause" : "Play")
            .help(configuration.controller.isPlaying ? "Pause" : "Play")

            Text(timeLabel(configuration.controller.currentTime))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize()

            ProjectPlaybackWaveform(
                samples: configuration.waveformSamples,
                currentTime: configuration.controller.currentTime,
                duration: configuration.controller.duration,
                onScrub: { time in
                    configuration.controller.scrub(to: time)
                },
                onScrubEnd: configuration.controller.endScrub
            )
            .frame(height: 30)

            Text(timeLabel(configuration.controller.duration))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.66))
                .fixedSize()

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            Button {
                configuration.controller.setPlaybackRate(nextPlaybackRate)
            } label: {
                Text(configuration.controller.playbackRate.displayName)
                    .monospacedDigit()
                    .frame(width: 32, height: 24)
            }
            .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
            .pointingHandCursor()
            .accessibilityLabel("Playback speed")
            .accessibilityValue(configuration.controller.playbackRate.displayName)
            .help("Playback speed · Click for \(nextPlaybackRate.displayName)")
        }
    }

    private var nextPlaybackRate: EditorPlaybackRate {
        switch configuration.controller.playbackRate {
        case .normal: .oneAndAHalf
        case .oneAndAHalf: .double
        case .double, .twoAndAHalf: .normal
        }
    }

    private func timeLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ProjectPlaybackWaveform: View {
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
                let values = samples.isEmpty
                    ? [Float](repeating: 0, count: 120)
                    : samples
                let slot = size.width / CGFloat(values.count)
                let barWidth = max(1, min(2.5, slot * 0.58))
                let maxHeight = max(1, size.height - 4)
                let playedWidth = size.width * progress

                for (index, value) in values.enumerated() {
                    let amplitude = samples.isEmpty ? 0.08 : min(1, max(0, value))
                    let height = max(2, CGFloat(amplitude) * maxHeight)
                    let x = CGFloat(index) * slot + (slot - barWidth) / 2
                    let bar = CGRect(
                        x: x,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    let color = bar.midX <= playedWidth
                        ? BlitzUI.mint.opacity(0.92)
                        : Color.white.opacity(samples.isEmpty ? 0.15 : 0.38)
                    context.fill(
                        Path(roundedRect: bar, cornerRadius: barWidth / 2),
                        with: .color(color)
                    )
                }

                let playhead = CGRect(
                    x: min(max(playedWidth - 0.5, 0), max(0, size.width - 1)),
                    y: 1,
                    width: 1,
                    height: max(0, size.height - 2)
                )
                context.fill(
                    Path(roundedRect: playhead, cornerRadius: 0.5),
                    with: .color(.white.opacity(0.88))
                )
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(time(.init(
                            x: value.location.x,
                            width: proxy.size.width
                        )))
                    }
                    .onEnded { _ in
                        onScrubEnd()
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Playback waveform")
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

    private func timeLabel(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
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
        .buttonStyle(BlitzControlButtonStyle(isProminent: configuration.tone == .primary))
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
        .buttonStyle(BlitzControlButtonStyle(isProminent: false))
        .pointingHandCursor()
        .help(configuration.title)
        .accessibilityLabel(configuration.title)
    }
}
