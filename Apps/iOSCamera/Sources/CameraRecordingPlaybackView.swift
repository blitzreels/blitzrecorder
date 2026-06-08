import AVFoundation
import SwiftUI
import UIKit

struct CameraRecordingPlaybackView: View {
    let recording: CameraPendingRecording
    let retryImport: () -> Void
    let delete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playback: CameraRecordingPlaybackModel
    @State private var zoomResetToken = 0

    init(
        recording: CameraPendingRecording,
        retryImport: @escaping () -> Void,
        delete: @escaping () -> Void
    ) {
        self.recording = recording
        self.retryImport = retryImport
        self.delete = delete
        _playback = State(initialValue: CameraRecordingPlaybackModel(url: recording.url))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CompanionTheme.canvasTop, CompanionTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            CompanionStudioGrid()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZoomablePlayerSurface(player: playback.player, resetToken: zoomResetToken)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(playback.displayAspectRatio, contentMode: .fit)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(CompanionTheme.stroke, lineWidth: 1)
                        }
                        .accessibilityLabel("Recording preview")

                    playbackControls

                    metadata
                }
                .padding()
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    retryImport()
                } label: {
                    Label("Send Again", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(recording.takeID == nil)

                Button(role: .destructive) {
                    playback.pause()
                    delete()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .onAppear {
            playback.start()
        }
        .onDisappear {
            playback.pause()
        }
        .tint(CompanionTheme.accent)
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    playback.togglePlayback()
                } label: {
                    Label(
                        playback.isPlaying ? "Pause" : "Play",
                        systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                    )
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(CompanionTheme.accent)
                .clipShape(Circle())

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { playback.currentSeconds },
                            set: { playback.scrub(to: $0) }
                        ),
                        in: 0...playback.seekableDuration,
                        onEditingChanged: playback.setScrubbing
                    )
                    .disabled(!playback.canSeek)

                    HStack {
                        Text(playback.currentTimeLabel)
                        Spacer()
                        Text(playback.durationLabel)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CompanionTheme.faintText)
                }
            }

            Button {
                zoomResetToken += 1
            } label: {
                Label("Reset view", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))

            if let message = playback.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(CompanionTheme.faintText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .foregroundStyle(.white)
        .companionGlassPanel(cornerRadius: 18)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Created", value: recording.createdAtLabel)
            LabeledContent("File", value: recording.fileName)
            LabeledContent("Size", value: recording.byteCountLabel)
            LabeledContent("Resolution", value: playback.resolutionLabel)
            LabeledContent("Codec", value: playback.codecLabel)
            LabeledContent("Frame rate", value: playback.frameRateLabel)
        }
        .font(.subheadline)
        .padding()
        .foregroundStyle(.white)
        .companionGlassPanel(cornerRadius: 18)
    }
}

@MainActor
@Observable
private final class CameraRecordingPlaybackModel {
    let player: AVPlayer

    var currentSeconds = 0.0
    var durationSeconds = 0.0
    var isPlaying = false
    var statusMessage: String?
    var displayAspectRatio = 9.0 / 16.0
    var resolutionLabel = "Loading"
    var codecLabel = "Loading"
    var frameRateLabel = "Loading"

    private var isScrubbing = false
    private var didLoadDuration = false
    private var timeObserver: Any?
    private var metadataTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    init(url: URL) {
        player = AVPlayer(url: url)
        loadMetadata(from: url)
    }

    deinit {
        MainActor.assumeIsolated {
            tearDown()
        }
    }

    var canSeek: Bool {
        durationSeconds.isFinite && durationSeconds > 0
    }

    var seekableDuration: Double {
        max(durationSeconds, 0.1)
    }

    var currentTimeLabel: String {
        Self.timeLabel(for: currentSeconds)
    }

    var durationLabel: String {
        canSeek ? Self.timeLabel(for: durationSeconds) : "--:--"
    }

    func start() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateCurrentTime(time)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.didFinishPlayback()
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            if canSeek, currentSeconds >= durationSeconds {
                seek(to: 0)
            }
            statusMessage = nil
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func tearDown() {
        pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        metadataTask?.cancel()
        metadataTask = nil
    }

    func scrub(to seconds: Double) {
        currentSeconds = clamped(seconds)
    }

    func setScrubbing(_ isEditing: Bool) {
        isScrubbing = isEditing
        guard !isEditing else { return }
        seek(to: currentSeconds)
    }

    private func loadMetadata(from url: URL) {
        metadataTask?.cancel()
        metadataTask = Task {
            let asset = AVURLAsset(url: url)
            do {
                let duration = try await asset.load(.duration)
                guard !Task.isCancelled else { return }
                let seconds = duration.seconds
                durationSeconds = seconds.isFinite ? max(seconds, 0) : 0
                didLoadDuration = true
                statusMessage = durationSeconds > 0 ? nil : "Length not available"

                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    resolutionLabel = "No video track"
                    codecLabel = "Unknown"
                    frameRateLabel = "Unknown"
                    return
                }

                let naturalSize = try await videoTrack.load(.naturalSize)
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                let orientedRect = CGRect(origin: .zero, size: naturalSize)
                    .applying(preferredTransform)
                    .standardized
                let width = abs(orientedRect.width)
                let height = abs(orientedRect.height)
                if width > 0, height > 0 {
                    displayAspectRatio = Double(width / height)
                    resolutionLabel = "\(Int(width.rounded()))x\(Int(height.rounded()))"
                } else {
                    resolutionLabel = "Unknown"
                }

                let frameRate = try await videoTrack.load(.nominalFrameRate)
                frameRateLabel = frameRate > 0
                    ? "\(Self.trimmed(frameRate)) fps"
                    : "Variable/unknown"

                let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                codecLabel = Self.codecLabel(for: formatDescriptions.first)
            } catch {
                guard !Task.isCancelled else { return }
                didLoadDuration = true
                statusMessage = "Couldn’t read clip length"
                resolutionLabel = "Unknown"
                codecLabel = "Unknown"
                frameRateLabel = "Unknown"
            }
        }
    }

    private func updateCurrentTime(_ time: CMTime) {
        if !didLoadDuration, let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
            durationSeconds = max(itemDuration, 0)
        }
        guard !isScrubbing else { return }
        currentSeconds = clamped(time.seconds)
        isPlaying = player.timeControlStatus == .playing
    }

    private func didFinishPlayback() {
        currentSeconds = durationSeconds
        isPlaying = false
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: clamped(seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clamped(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        if canSeek {
            return min(max(seconds, 0), durationSeconds)
        }
        return max(seconds, 0)
    }

    private static func timeLabel(for seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static func codecLabel(for formatDescription: CMFormatDescription?) -> String {
        guard let formatDescription else { return "Unknown" }
        let codec = CMFormatDescriptionGetMediaSubType(formatDescription)
        switch codec {
        case kCMVideoCodecType_HEVC:
            return "HEVC"
        case kCMVideoCodecType_H264:
            return "H.264"
        case kCMVideoCodecType_AppleProRes422:
            return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444:
            return "ProRes 4444"
        default:
            return fourCharacterCode(codec)
        }
    }

    private static func fourCharacterCode(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
    }

    private static func trimmed(_ value: Float) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.2f", value)
    }
}

private struct ZoomablePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let resetToken: Int

    func makeUIView(context: Context) -> ZoomablePlayerScrollView {
        let view = ZoomablePlayerScrollView()
        view.configure(player: player, resetToken: resetToken)
        return view
    }

    func updateUIView(_ view: ZoomablePlayerScrollView, context: Context) {
        view.configure(player: player, resetToken: resetToken)
    }
}

private final class ZoomablePlayerScrollView: UIScrollView, UIScrollViewDelegate {
    private let playerView = PlayerLayerView()
    private var currentResetToken = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        playerView.backgroundColor = .black
        addSubview(playerView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == minimumZoomScale {
            playerView.frame = bounds
            contentSize = bounds.size
        }
        centerContent()
    }

    func configure(player: AVPlayer, resetToken: Int) {
        playerView.player = player
        if playerView.frame == .zero {
            playerView.frame = bounds
            contentSize = bounds.size
        }
        guard resetToken != currentResetToken else { return }
        currentResetToken = resetToken
        setZoomScale(minimumZoomScale, animated: true)
        playerView.frame = bounds
        contentSize = bounds.size
        centerContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        playerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
    }

    private func centerContent() {
        let horizontalInset = max(0, (bounds.width - contentSize.width) / 2)
        let verticalInset = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
}

private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
