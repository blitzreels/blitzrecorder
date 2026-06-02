import AppKit
import AVFoundation
import Foundation
import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(spacing: 12) {
            if vm.state != .idle {
                SessionProgressView(vm: vm)
            } else if let recovery = vm.lastRecoveryOutput {
                RecoveryAvailableView(vm: vm, recovery: recovery)
            } else if !vm.canStartRecording {
                ReadinessIssueView(vm: vm)
            } else if let savedURL = vm.lastExportedURL {
                ExportCompletedView(
                    vm: vm,
                    url: savedURL,
                    sourceTakeURL: vm.lastExportedSourceTakeURL,
                    warning: vm.lastExportWarning
                )
            } else if let message = vm.idleStatusMessage {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 300)
            }

            RecordingActionRow(vm: vm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    var body: some View {
        HStack(spacing: 12) {
            // Leading cluster
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
            .frame(maxWidth: .infinity, alignment: .leading)

            RecordButton(vm: vm)

            // Trailing balancer keeps the record button centered. The old "Recordings"
            // shortcut lived here but was redundant — it only opened export settings,
            // exactly like the EXPORT chip on the left.
            HStack(spacing: 10) {}
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
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

private struct ExportCompletedView: View {
    @Bindable var vm: RecorderViewModel
    let url: URL
    let sourceTakeURL: URL?
    let warning: String?
    @State private var metadata = RecordingFileMetadata.empty

    private let accent = BlitzUI.mint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Info header — kept free of buttons so the filename never squeezes the actions.
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("RECORDING SAVED")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(accent.opacity(0.9))
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.lastPathComponent)
                    Text(savedDetail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folderPath)
                }

                Spacer(minLength: 0)
            }

            if let warning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BlitzUI.warning)
                        .frame(width: 16)
                    Text(warning)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(warning)
                }
            }

            if let sourceTakeURL {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 16)
                    Text("Sources saved: \(sourceTakeURL.lastPathComponent)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(sourceTakeURL.path)

                    Spacer(minLength: 8)

                    DockActionButton(title: "Sources", systemImage: "tray.full", help: sourceTakeURL.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([sourceTakeURL])
                    }
                }
            }

            Divider()
                .background(.white.opacity(0.07))

            // Actions on their own full-width row — plenty of room, nothing truncates.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
                DockActionButton(title: "Open", systemImage: "play.fill", help: "Open \(url.lastPathComponent)") {
                    NSWorkspace.shared.open(url)
                }
                DockActionButton(title: "Reveal", systemImage: "folder", help: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                DockActionButton(title: "Rename", systemImage: "pencil", help: "Rename or move this finished recording") {
                    vm.renameLastExportedFile()
                }

                DockActionButton(title: "New Take", systemImage: "plus", help: "Clear and get ready for the next recording") {
                    vm.clearPostRecordingStatus()
                }
            }
        }
        .frame(maxWidth: 460)
        .task(id: url) {
            metadata = .empty
            metadata = await RecordingFileMetadata.load(for: url)
        }
    }

    private var folderPath: String {
        url.deletingLastPathComponent().path
    }

    private var folderLabel: String {
        (folderPath as NSString).abbreviatingWithTildeInPath
    }

    private var savedDetail: String {
        let parts = [folderLabel] + metadata.labels
        return "Saved to \(parts.joined(separator: " · "))"
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

    static let empty = RecordingFileMetadata(sizeLabel: nil, durationLabel: nil)

    var labels: [String] {
        [sizeLabel, durationLabel].compactMap { $0 }
    }

    static func load(for url: URL) async -> RecordingFileMetadata {
        async let sizeLabel = fileSizeLabel(for: url)
        async let durationLabel = durationLabel(for: url)
        return await RecordingFileMetadata(sizeLabel: sizeLabel, durationLabel: durationLabel)
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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            DetailsLink { vm.openReadinessDetails() }
        }
        .frame(maxWidth: .infinity)
    }

    private var message: String {
        if !vm.accessController.canRenderExport {
            return "Free exports used"
        }
        return vm.recordingReadiness.blockers.first?.sentence ?? vm.recordingReadiness.detail
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

private struct SessionProgressView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        switch vm.state {
        case .recording, .paused:
            RecordingElapsedView(state: vm.state, elapsed: vm.formattedElapsed)
        case .starting:
            StartingRecordingView(title: vm.sessionProgressTitle, detail: vm.sessionProgressDetail)
        case .finishing:
            RenderingProgressView(
                title: vm.sessionProgressTitle,
                detail: vm.sessionProgressDetail,
                progress: vm.sessionProgressValue,
                percent: vm.sessionProgressLabel
            )
        case .idle:
            EmptyView()
        }
    }
}

private struct StartingRecordingView: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Text(detail ?? "Not recording yet. Hang on while capture gets ready.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        }
        .frame(maxWidth: 360)
    }
}

private struct RecordingElapsedView: View {
    let state: RecordingState
    let elapsed: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state == .paused ? "pause.fill" : "record.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state == .paused ? BlitzUI.warning : BlitzUI.recordRed)
                .frame(width: 16)
            Text(state == .paused ? "Paused" : "Recording")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 12)
            Text(elapsed)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(minWidth: 160, maxWidth: 224)
    }
}

private struct RenderingProgressView: View {
    let title: String
    let detail: String?
    let progress: Double
    let percent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                Text(percent)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
            }

            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.85))
        }
        .frame(maxWidth: 360)
    }
}

private struct PauseButton: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.togglePause()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
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

    private let diameter: CGFloat = 64
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
                    .frame(width: 20, height: 20)
            }
        case .starting, .finishing:
            ProgressView()
                .controlSize(.small)
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
