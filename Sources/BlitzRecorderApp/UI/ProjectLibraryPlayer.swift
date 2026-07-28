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
        VStack(spacing: 12) {
            videoSurface

            if isPlaybackReady {
                transportControls
                    .frame(width: playerLayout.transportWidth)
                    .transition(.opacity)
            }
        }
        .frame(width: playerLayout.transportWidth)
        .animation(.easeOut(duration: 0.18), value: isPlaybackReady)
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
                    previewSceneRevision: configuration.controller.previewSceneRevision
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }

        }
        .frame(width: playerLayout.videoSize.width, height: playerLayout.videoSize.height)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.44), radius: 28, y: 14)
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

    private var transportControls: some View {
        HStack(spacing: 10) {
            Button {
                configuration.controller.togglePlayback()
            } label: {
                Image(systemName: configuration.controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .offset(x: configuration.controller.isPlaying ? 0 : 1)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.10), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(ProjectPlayerPressButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            .pointingHandCursor()
            .help(configuration.controller.isPlaying ? "Pause" : "Play")

            Text(timeLabel(configuration.controller.currentTime))
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 34, alignment: .trailing)

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
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 34, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.76), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
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
    @State private var isHovering = false

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 9) {
                if configuration.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: configuration.systemImage)
                        .font(.system(size: 12, weight: .bold))
                }

                Text(configuration.title)
                    .font(.system(size: 12, weight: .bold))

                if configuration.tone == .primary {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .heavy))
                        .opacity(isHovering ? 0.92 : 0.62)
                        .offset(x: isHovering ? 2 : 0)
                }
            }
            .foregroundStyle(foregroundStyle)
            .padding(.leading, 16)
            .padding(.trailing, configuration.tone == .primary ? 14 : 16)
            .frame(height: 44)
            .background(backgroundStyle, in: .rect(cornerRadius: 11))
            .overlay {
                if configuration.tone == .secondary {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(isHovering ? 0.13 : 0.08), lineWidth: 1)
                }
            }
            .shadow(
                color: shadowColor,
                radius: isHovering ? 14 : 8,
                y: isHovering ? 6 : 3
            )
            .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(ProjectPlayerPressButtonStyle())
        .disabled(configuration.isLoading)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .pointingHandCursor()
    }

    private var foregroundStyle: Color {
        switch configuration.tone {
        case .primary:
            return .black.opacity(0.86)
        case .secondary:
            return .white.opacity(isHovering ? 0.90 : 0.72)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch configuration.tone {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        BlitzUI.mint,
                        BlitzUI.mint.opacity(isHovering ? 0.88 : 0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .secondary:
            return AnyShapeStyle(.white.opacity(isHovering ? 0.085 : 0.055))
        }
    }

    private var shadowColor: Color {
        switch configuration.tone {
        case .primary:
            return BlitzUI.mint.opacity(isHovering ? 0.22 : 0.10)
        case .secondary:
            return .black.opacity(isHovering ? 0.24 : 0.14)
        }
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
    @State private var isHovering = false

    var body: some View {
        Button(action: configuration.action) {
            Image(systemName: configuration.systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 42, height: 42)
                .background(backgroundStyle, in: .rect(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(outlineStyle, lineWidth: 1)
                }
                .shadow(
                    color: .black.opacity(isHovering ? 0.24 : 0.12),
                    radius: isHovering ? 10 : 5,
                    y: isHovering ? 5 : 2
                )
                .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(ProjectPlayerPressButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .pointingHandCursor()
        .help(configuration.title)
        .accessibilityLabel(configuration.title)
    }

    private var foregroundStyle: Color {
        switch configuration.tone {
        case .secondary:
            return .white.opacity(isHovering ? 0.92 : 0.70)
        case .destructive:
            return .red.opacity(isHovering ? 0.96 : 0.76)
        }
    }

    private var backgroundStyle: Color {
        switch configuration.tone {
        case .secondary:
            return .white.opacity(isHovering ? 0.085 : 0.050)
        case .destructive:
            return .red.opacity(isHovering ? 0.13 : 0.075)
        }
    }

    private var outlineStyle: Color {
        switch configuration.tone {
        case .secondary:
            return .white.opacity(isHovering ? 0.13 : 0.075)
        case .destructive:
            return .red.opacity(isHovering ? 0.24 : 0.14)
        }
    }
}

private struct ProjectPlayerPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
