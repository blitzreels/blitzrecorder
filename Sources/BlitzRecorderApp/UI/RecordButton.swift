import SwiftUI

struct PauseButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var hovering = false

    var body: some View {
        Button {
            vm.togglePause()
        } label: {
            ZStack {
                Circle()
                    .fill(hovering && isEnabled ? BlitzUI.strongFill : BlitzUI.selectedFill)
                Image(systemName: symbol)
                    .font(BlitzType.glyph(15))
                    .foregroundStyle(BlitzUI.primaryText)
            }
            .frame(width: 48, height: 48)
            .contentShape(.circle)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .pointingHandCursor()
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

    @State private var isHovering = false

    var body: some View {
        Button {
            vm.primaryAction()
        } label: {
            HStack(spacing: 9) {
                recordGlyph
                Text(actionTitle)
                    .font(BlitzType.section)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .frame(minWidth: vm.state == .idle ? 128 : 100, minHeight: 48)
            .background(buttonFill, in: .capsule)
            .shadow(color: BlitzUI.recordRed.opacity(isHovering && enabled ? 0.45 : 0.25), radius: 12, y: 3)
            .contentShape(.capsule)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
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
                .frame(width: 12, height: 12)
        case .recording, .paused:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(BlitzUI.primaryText)
                .frame(width: 12, height: 12)
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .finishing:
            ProgressView()
                .controlSize(.small)
        }
    }

    private var buttonFill: Color {
        BlitzUI.recordRed.opacity(isHovering && enabled ? 1 : 0.88)
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
