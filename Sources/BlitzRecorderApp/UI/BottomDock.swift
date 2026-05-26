import AVFoundation
import Foundation
import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        BlitzGlassContainer(spacing: 12) {
            VStack(spacing: 12) {
                if vm.state != .idle {
                    SessionProgressView(vm: vm)
                } else if !vm.canStartRecording {
                    ReadinessIssueView(vm: vm)
                } else if let savedURL = vm.lastExportedURL {
                    ExportCompletedView(
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
                        .frame(width: 300)
                }

                RecordingActionRow(vm: vm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .blitzGlassSurface(cornerRadius: 26)
    }
}

private struct RecordingActionRow: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 10) {
            switch vm.state {
            case .idle:
                RecordingSettingsShortcut(vm: vm)
                RecordButton(vm: vm)
            case .recording, .paused:
                PauseButton(vm: vm)
                RecordButton(vm: vm)
            case .starting, .finishing:
                RecordButton(vm: vm)
            }
        }
    }
}

private struct RecordingSettingsShortcut: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.appTab = .recording
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Export")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.44))
                    Text(settingsSummary)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(width: 142)
        }
        .blitzGlassButton()
        .pointingHandCursor()
        .help("Open export settings")
    }

    private var settingsSummary: String {
        "\(vm.settings.outputResolution.displayName) · \(vm.settings.framesPerSecond) FPS"
    }
}

private struct ExportCompletedView: View {
    let url: URL
    let sourceTakeURL: URL?
    let warning: String?
    @State private var metadata = RecordingFileMetadata.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.09, green: 1.0, blue: 0.65))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording saved")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.09, green: 1.0, blue: 0.65).opacity(0.9))
                    Text(url.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(savedDetail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(folderPath)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    OpenFileButton(title: "Open", systemImage: "play.fill", url: url)
                    FinderButton(title: "Reveal", systemImage: "folder", url: url)
                }
            }

            if let warning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow.opacity(0.92))
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

                    FinderButton(title: "Sources", systemImage: "tray.full", url: sourceTakeURL)
                }
            }
        }
        .frame(width: 360)
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

private struct OpenFileButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .help("Open \(url.lastPathComponent)")
    }
}

private struct FinderButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .help(url.path)
    }
}

private struct ReadinessIssueView: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.yellow.opacity(0.92))

            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                vm.openReadinessDetails()
            } label: {
                Text("Details")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()
        }
        .frame(width: 300)
    }

    private var message: String {
        if !vm.accessController.canRenderExport {
            return "Free exports used"
        }
        return vm.recordingReadiness.blockers.first?.sentence ?? vm.recordingReadiness.detail
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
                    .fill(Color(red: 0.27, green: 0.7, blue: 1).opacity(0.16))
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.5, green: 0.82, blue: 1))
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
        .frame(width: 360)
    }
}

private struct RecordingElapsedView: View {
    let state: RecordingState
    let elapsed: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state == .paused ? "pause.fill" : "record.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state == .paused ? .yellow.opacity(0.9) : .red.opacity(0.95))
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
        .frame(width: 224)
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
        .frame(width: 360)
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

private struct RecordButton: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.primaryAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 168)
        }
        .blitzProminentGlassButton()
        .tint(tint)
        .disabled(!enabled)
        .pointingHandCursor()
        .help(vm.recordingBlockerDetail ?? "")
    }

    private var symbol: String {
        switch vm.state {
        case .idle: return "record.circle"
        case .recording, .paused: return "stop.fill"
        case .starting: return "hourglass"
        case .finishing: return "ellipsis"
        }
    }

    private var label: String {
        switch vm.state {
        case .idle: return "Start Recording"
        case .recording, .paused: return "Stop"
        case .starting: return "Please Wait"
        case .finishing: return "Saving…"
        }
    }

    private var tint: Color {
        switch vm.state {
        case .idle:
            return vm.canStartRecording ? Color(red: 1, green: 0.27, blue: 0.27) : .yellow
        case .recording, .paused: return Color(red: 0.9, green: 0.9, blue: 0.95)
        case .starting, .finishing: return .gray
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
