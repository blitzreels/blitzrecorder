import AppKit
import AVFoundation
import Foundation
import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        // One fixed-height transport row for every session state; only the rare
        // idle-time problems (recovery, readiness) still stack a banner above it.
        VStack(spacing: 10) {
            if vm.state == .idle {
                if let recovery = vm.lastRecoveryOutput {
                    RecoveryAvailableView(vm: vm, recovery: recovery)
                } else if !vm.canStartRecording {
                    ReadinessIssueView(vm: vm)
                }
            }

            RecordingActionRow(vm: vm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct RecordingActionRow: View {
    @Bindable var vm: RecorderViewModel
    /// Preview-only escape hatch: readiness checks need live permissions, which
    /// render previews never have.
    var forcesSavedChip = false

    var body: some View {
        // Both side clusters hug the record button with equal gaps — one symmetric
        // transport cluster around the hero, not satellites scattered to the edges.
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                switch vm.state {
                case .idle:
                    RecordingSettingsShortcut(vm: vm)
                case .recording, .paused:
                    PauseButton(vm: vm)
                case .starting, .finishing:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            RecordButton(vm: vm)

            // Trailing slot: session status or the saved-take chip — always IN
            // the row, never stacked above it, so the dock height holds still.
            HStack(spacing: 10) {
                switch vm.state {
                case .idle:
                    if let savedURL = savedExportURL {
                        SavedRecordingChip(
                            vm: vm,
                            url: savedURL,
                            sourceTakeURL: vm.lastExportedSourceTakeURL,
                            warning: vm.lastExportWarning
                        )
                    } else if let message = vm.idleStatusMessage {
                        // Transient status ("Fitted <window>…") rides in the row
                        // like everything else; never cut mid-sentence.
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 320, alignment: .leading)
                            .help(message)
                    }
                case .starting:
                    // The record button's spinner is the ONLY loading indicator;
                    // this is just words.
                    SessionStatusText(title: vm.sessionProgressTitle, detail: vm.sessionProgressDetail)
                case .recording, .paused:
                    ElapsedTimeText(isPaused: vm.state == .paused, elapsed: vm.formattedElapsed)
                case .finishing:
                    FinishingProgressStatus(
                        title: vm.sessionProgressTitle,
                        detail: vm.sessionProgressDetail,
                        progress: vm.sessionProgressValue,
                        percent: vm.sessionProgressLabel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Same precedence the stacked dock used: recovery and readiness issues win,
    /// and a new session hides the previous take.
    private var savedExportURL: URL? {
        if forcesSavedChip { return vm.lastExportedURL }
        guard vm.state == .idle,
              vm.lastRecoveryOutput == nil,
              vm.canStartRecording else { return nil }
        return vm.lastExportedURL
    }
}

/// Idle dock control: shows the export quality + FPS and opens export settings on
/// click. One quiet line — a small gear glyph for affordance + the value, with no
/// "EXPORT" eyebrow and no box (that chip read as cluttered). Text brightens on hover.
private struct RecordingSettingsShortcut: View {
    @Bindable var vm: RecorderViewModel
    @State private var hovering = false

    var body: some View {
        Button {
            vm.onPresentSettings?(.recording)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(settingsSummary)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
            .foregroundStyle(.white.opacity(hovering ? 0.92 : 0.58))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help("Export settings")
    }

    private var settingsSummary: String {
        "\(vm.settings.outputResolution.displayName) · \(vm.settings.framesPerSecond) FPS"
    }
}

/// A compact glass button for dock actions. `fixedSize()` keeps the label at its natural
/// width so it can never truncate, no matter how tight the surrounding row is.
private struct DockActionButton: View {
    let title: String
    let systemImage: String
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold))
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .help(help ?? title)
    }
}

/// Compact "last take" chip beside the record button — two click targets, zero
/// toolbar. Thumbnail = play; the text block = show in Finder; everything else
/// (rename, sources, clear) lives in the right-click menu. Only the quiet ✕
/// surfaces on hover. At rest it reads as one calm object.
private struct SavedRecordingChip: View {
    @Bindable var vm: RecorderViewModel
    let url: URL
    let sourceTakeURL: URL?
    let warning: String?
    @State private var metadata = RecordingFileMetadata.empty
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RecordingThumbnailButton(
                image: metadata.thumbnail,
                durationLabel: metadata.durationLabel,
                height: 40,
                help: "Play \(url.lastPathComponent)"
            ) {
                NSWorkspace.shared.open(url)
            }

            SavedRecordingSummaryButton(detail: savedDetail, path: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BlitzUI.warning)
                    .help(warning)
            }

            DockDismissButton(help: "Clear and get ready for the next take") {
                vm.clearPostRecordingStatus()
            }
            .opacity(hovering ? 1 : 0)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Play") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Rename…") { vm.renameLastExportedFile() }
            if let sourceTakeURL {
                Button("Show Source Files") {
                    NSWorkspace.shared.activateFileViewerSelecting([sourceTakeURL])
                }
            }
            Divider()
            Button("Clear") { vm.clearPostRecordingStatus() }
        }
        .task(id: url) {
            metadata = .empty
            metadata = await RecordingFileMetadata.load(for: url)
        }
    }

    private var savedDetail: String {
        // Filename + size; the full path lives in the hover tooltip, the duration
        // on the thumbnail badge (fall back here when there's no thumbnail).
        var parts = [url.lastPathComponent]
        if metadata.thumbnail == nil, let durationLabel = metadata.durationLabel {
            parts.append(durationLabel)
        }
        if let sizeLabel = metadata.sizeLabel {
            parts.append(sizeLabel)
        }
        return parts.joined(separator: " · ")
    }
}

/// The chip's two text lines as one click target (→ Finder). The headline never
/// compresses; only the detail line truncates when the dock gets tight.
private struct SavedRecordingSummaryButton: View {
    let detail: String
    let path: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BlitzUI.mint.opacity(0.9))
                    Text("Recording saved")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize()
                }
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(hovering ? 0.78 : 0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 230, alignment: .leading)
        .layoutPriority(1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help("Show in Finder — \(path)")
    }
}

/// Quiet words beside the record button while capture spins up — the button's
/// spinner is the only loading indicator, deliberately.
private struct SessionStatusText: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(detail)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }
}

/// The running clock beside the record button. Paused = dimmed digits + amber word.
private struct ElapsedTimeText: View {
    let isPaused: Bool
    let elapsed: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(elapsed)
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isPaused ? 0.55 : 0.95))
            if isPaused {
                Text("Paused")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BlitzUI.warning)
            }
        }
    }
}

/// Compact export progress beside the record button — title, percent, one bar.
private struct FinishingProgressStatus: View {
    let title: String
    let detail: String?
    let progress: Double
    let percent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Text(percent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.85))
                .frame(width: 200)
        }
        .help(detail ?? title)
    }
}

/// The recording's first frame as a click-to-play tile. Fixed height; width follows the
/// video's aspect (vertical shorts stay narrow, screen takes go wide) within sane bounds.
/// Hover dims the frame and surfaces a play glyph, like QuickLook.
private struct RecordingThumbnailButton: View {
    let image: NSImage?
    let durationLabel: String?
    var height: CGFloat = 68
    let help: String
    let action: () -> Void
    @State private var hovering = false

    private var width: CGFloat {
        guard let image, image.size.height > 0 else { return height * 16 / 9 }
        let ideal = height * image.size.width / image.size.height
        return min(max(ideal, height * 0.6), height * 1.9)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                    Image(systemName: "film")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }

                Rectangle()
                    .fill(.black.opacity(hovering ? 0.35 : 0))
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .bottomTrailing) {
                if let durationLabel {
                    Text(durationLabel)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(4)
                        .opacity(hovering ? 0 : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help(help)
    }
}

/// A quiet ✕ — no button chrome, brightens on hover.
private struct DockDismissButton: View {
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.45))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
        .help(help)
    }
}

private struct RecoveryAvailableView: View {
    @Bindable var vm: RecorderViewModel
    let recovery: RecordingRecoveryOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BlitzUI.warning)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording needs recovery")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BlitzUI.warning)
                    Text(recovery.reason)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recovery.takeDirectory.path)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(recovery.takeDirectory.path)
                }

                Spacer(minLength: 8)
            }

            Divider()
                .background(.white.opacity(0.07))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                if recovery.canRetryExport {
                    DockActionButton(title: "Retry Export", systemImage: "arrow.clockwise", help: "Try exporting the recovered source files again") {
                        vm.retryRecoveredExport()
                    }
                }

                DockActionButton(title: "Reveal Files", systemImage: "tray.full", help: recovery.takeDirectory.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([recovery.takeDirectory])
                }

                DockActionButton(title: "Export Settings", systemImage: "slider.horizontal.3") {
                    vm.onPresentSettings?(.recording)
                }

                DockActionButton(title: "Dismiss", systemImage: "xmark") {
                    vm.clearPostRecordingStatus()
                }
            }
        }
        .frame(maxWidth: 460)
    }
}

private struct RecordingFileMetadata {
    let sizeLabel: String?
    let durationLabel: String?
    let thumbnail: NSImage?

    static let empty = RecordingFileMetadata(sizeLabel: nil, durationLabel: nil, thumbnail: nil)

    static func load(for url: URL) async -> RecordingFileMetadata {
        async let sizeLabel = fileSizeLabel(for: url)
        async let durationLabel = durationLabel(for: url)
        async let thumbnail = thumbnail(for: url)
        return await RecordingFileMetadata(sizeLabel: sizeLabel, durationLabel: durationLabel, thumbnail: thumbnail)
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let (cgImage, _) = try? await generator.image(at: .zero) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func fileSizeLabel(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let byteCount = attributes[.size] as? NSNumber else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: byteCount.int64Value, countStyle: .file)
    }

    private static func durationLabel(for url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.isValid,
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            return nil
        }
        return formattedDuration(seconds: duration.seconds)
    }

    private static func formattedDuration(seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ReadinessIssueView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BlitzUI.warning)

            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(fullExplanation)

            Spacer(minLength: 12)

            DetailsLink { vm.openReadinessDetails() }
        }
        .frame(maxWidth: .infinity)
    }

    // Short and human; the full technical sentence lives in the hover tooltip and
    // the Permissions tab behind "Details".
    private var message: String {
        if !vm.accessController.canRenderExport {
            return "Recording unavailable"
        }
        let blockers = vm.recordingReadiness.blockers
        return blockers.isEmpty ? vm.recordingReadiness.detail : blockers.shortSummary
    }

    private var fullExplanation: String {
        let sentences = vm.recordingReadiness.blockers.map(\.sentence)
        return sentences.isEmpty ? message : sentences.joined(separator: "\n")
    }
}

/// A quiet text affordance ("Details ›") — no button chrome, brightens on hover.
private struct DetailsLink: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("Details")
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(hovering ? 1 : 0.78))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHandCursor()
    }
}

private struct PauseButton: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.togglePause()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 40, height: 40)
        }
        .blitzGlassButton()
        .disabled(!isEnabled)
        .pointingHandCursor()
        .help(helpText)
    }

    private var symbol: String {
        vm.state == .paused ? "play.fill" : "pause.fill"
    }

    private var helpText: String {
        vm.state == .paused ? "Resume" : "Pause"
    }

    private var isEnabled: Bool {
        vm.state == .recording || vm.state == .paused
    }
}

/// Subtle press feedback for the record control — a small, calm dip, no bounce.
private struct RecordButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Round, Final Cut-style record control — the hero of the dock. Red is the ONLY
/// red in the UI. Idle = a flat solid-red disc inside a faint ring; recording/paused
/// = a red ring around a white stop square. Flat by design — no gradient, gloss, or
/// glow. Not-ready/locked states dim rather than recolor.
private struct RecordButton: View {
    @Bindable var vm: RecorderViewModel

    private let diameter: CGFloat = 56
    @State private var isHovering = false

    private var lifted: Bool { isHovering && enabled && !dimmed }

    var body: some View {
        Button {
            vm.primaryAction()
        } label: {
            ZStack {
                // Faint ring the disc sits inside (the classic record-button well).
                Circle()
                    .strokeBorder(.white.opacity(0.14), lineWidth: 2)
                    .frame(width: diameter, height: diameter)

                recordGlyph
            }
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .scaleEffect(lifted ? 1.03 : 1)
            .animation(.easeOut(duration: 0.16), value: lifted)
        }
        .buttonStyle(RecordButtonPressStyle())
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help(vm.recordingBlockerDetail ?? helpText)
    }

    @ViewBuilder
    private var recordGlyph: some View {
        switch vm.state {
        case .idle:
            Circle()
                .fill(BlitzUI.recordRed)
                .frame(width: diameter - 8, height: diameter - 8)
        case .recording, .paused:
            ZStack {
                Circle()
                    .strokeBorder(BlitzUI.recordRed, lineWidth: 4)
                    .frame(width: diameter - 6, height: diameter - 6)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.95))
                    .frame(width: 18, height: 18)
            }
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .finishing:
            // The linear export bar beside the button is the one progress
            // indicator; a spinner here would be a duplicate.
            Circle()
                .fill(BlitzUI.recordRed)
                .frame(width: diameter - 8, height: diameter - 8)
        }
    }

    private var helpText: String {
        switch vm.state {
        case .idle: return "Start recording"
        case .recording, .paused: return "Stop recording"
        case .starting: return "Please wait"
        case .finishing: return "Saving…"
        }
    }

    /// Idle-but-not-ready stays red but dims; we never turn it yellow (one red only).
    private var dimmed: Bool {
        switch vm.state {
        case .idle: return !vm.canStartRecording
        case .recording, .paused: return false
        case .starting, .finishing: return true
        }
    }

    private var enabled: Bool {
        switch vm.state {
        case .idle: return true
        case .recording, .paused: return true
        case .starting, .finishing: return false
        }
    }
}

#if DEBUG
@MainActor
private func bottomDockPreviewModel(warning: String? = nil) -> RecorderViewModel {
    let suiteName = "BlitzRecorder.BottomDockPreview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let coordinator = RecorderCoordinator(
        accessController: AccessController(defaults: defaults),
        defaults: defaults
    )
    let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
    // A real local file when available so the thumbnail/duration/size pipeline runs.
    vm.lastExportedURL = URL(fileURLWithPath: "/Volumes/harddrive/recordings/video-exa.mov")
    vm.lastExportedSourceTakeURL = URL(fileURLWithPath: "/Volumes/harddrive/recordings/sources/video-exa")
    vm.lastExportWarning = warning
    return vm
}

#Preview("Dock — recording saved") {
    RecordingActionRow(vm: bottomDockPreviewModel(), forcesSavedChip: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 1100)
        .background(.bar)
        .preferredColorScheme(.dark)
}

#Preview("Dock — saved with warning") {
    RecordingActionRow(
        vm: bottomDockPreviewModel(warning: "System audio was muted for part of this take."),
        forcesSavedChip: true
    )
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(width: 900)
    .background(.bar)
    .preferredColorScheme(.dark)
}
#endif
