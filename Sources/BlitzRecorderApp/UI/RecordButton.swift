import SwiftUI

struct PauseButton: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.togglePause()
        } label: {
            Image(systemName: symbol)
                .font(BlitzType.glyph(15))
                .foregroundStyle(BlitzUI.primaryText)
                .frame(width: BlitzControlMetrics.dockHeight - 36)
        }
        .blitzButton(.dock)
        .disabled(!isEnabled)
        .accessibilityLabel(helpText)
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

struct RecordButton: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Button {
            vm.primaryAction()
        } label: {
            HStack(spacing: 8) {
                recordGlyph
                Text(actionTitle)
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 112)
        }
        .blitzButton(.record)
        .controlSize(.extraLarge)
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
        .help(vm.recordingBlockerDetail ?? helpText)
    }

    @ViewBuilder
    private var recordGlyph: some View {
        switch vm.state {
        case .idle where vm.countdownRemaining != nil:
            Image(systemName: "xmark")
                .font(BlitzType.glyph(12))
                .foregroundStyle(.white)
        case .idle:
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
        case .recording, .paused:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.white)
                .frame(width: 14, height: 14)
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .finishing:
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

    private var actionTitle: String {
        switch vm.state {
        case .idle: return vm.countdownRemaining == nil ? "Record" : "Cancel"
        case .recording, .paused: return "Stop"
        case .starting: return "Starting"
        case .finishing: return "Saving"
        }
    }

    private var dimmed: Bool {
        switch vm.state {
        case .idle, .recording, .paused: return false
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
