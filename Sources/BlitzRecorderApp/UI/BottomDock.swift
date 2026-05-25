import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                if vm.state != .idle {
                    SessionProgressView(vm: vm)
                } else if !vm.canStartRecording {
                    ReadinessIssueView(vm: vm)
                } else if let savedURL = vm.lastExportedURL {
                    ExportCompletedView(url: savedURL)
                } else if let message = vm.idleStatusMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 300)
                }

                HStack(spacing: 12) {
                    PauseButton(vm: vm)
                    RecordButton(vm: vm)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}

private struct ExportCompletedView: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.09, green: 1.0, blue: 0.65))

            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .pointingHandCursor()
        }
        .frame(width: 300)
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
            .buttonStyle(.glass)
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
            RenderingProgressView(title: vm.sessionProgressTitle, detail: nil, progress: 0, percent: "0%")
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
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.white.opacity(0.85))
        }
        .frame(width: 224)
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
        .buttonStyle(.glass)
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
        .buttonStyle(.glassProminent)
        .tint(tint)
        .disabled(!enabled)
        .pointingHandCursor()
        .help(vm.recordingBlockerDetail ?? "")
    }

    private var symbol: String {
        switch vm.state {
        case .idle: return "record.circle"
        case .recording, .paused: return "stop.fill"
        case .starting: return "ellipsis"
        case .finishing: return "ellipsis"
        }
    }

    private var label: String {
        switch vm.state {
        case .idle: return "Start Recording"
        case .recording, .paused: return "Stop"
        case .starting: return "Starting..."
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
