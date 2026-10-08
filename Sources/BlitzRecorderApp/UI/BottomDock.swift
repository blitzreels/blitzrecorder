import SwiftUI

struct BottomDock: View {
    @Bindable var vm: RecorderViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if vm.state == .idle {
                if let recovery = vm.lastRecoveryOutput {
                    RecoveryAvailableView(vm: vm, recovery: recovery)
                        .floatingRecordingNotice()
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    RecorderSceneStrip(vm: vm)
                    RecordingActionRow(vm: vm)
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(spacing: 10) {
                    RecorderSceneStrip(vm: vm)
                    RecordingActionRow(vm: vm)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: vm.state)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: vm.canStartRecording)
    }
}

private extension View {
    func floatingRecordingNotice() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous)
                    .fill(.black.opacity(0.78))
                RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous)
                    .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
    }
}

private struct RecordingActionRow: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsScreenPicker = false
    var forcesSavedChip = false

    var body: some View {
        HStack(spacing: 8) {
            switch vm.state {
            case .idle:
                RecordButton(vm: vm)

                if let blocker = vm.dockRecordingBlockerSummary, vm.lastRecoveryOutput == nil {
                    Button(action: vm.primaryAction) {
                        Label(blocker, systemImage: "exclamationmark.circle.fill")
                            .font(BlitzType.captionEmphasis)
                            .foregroundStyle(BlitzUI.warning)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 170, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(vm.recordingBlockerDetail ?? blocker)
                }

                if let savedURL = savedExportURL {
                    TransportDivider()
                    SavedRecordingChip(
                        vm: vm,
                        url: savedURL,
                        sourceTakeURL: vm.lastExportedSourceTakeURL,
                        warning: vm.lastExportWarning
                    )
                }
            case .starting:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 40, height: 40)
                SessionStatusText(title: vm.sessionProgressTitle, detail: vm.sessionProgressDetail)
            case .recording, .paused:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        transportStatus
                        screenSwitchButton
                        RecordButton(vm: vm)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            transportStatus
                            RecordButton(vm: vm)
                        }
                        screenSwitchButton
                    }
                }
            case .finishing:
                FinishingProgressStatus(
                    title: vm.sessionProgressTitle,
                    detail: vm.sessionProgressDetail,
                    progress: vm.sessionProgressValue,
                    percent: vm.sessionProgressLabel,
                    startedAt: vm.finishingStartedAt
                )
            }
        }
        .frame(minHeight: 44)
    }

    private var transportStatus: some View {
        HStack(spacing: 8) {
            PauseButton(vm: vm)
            TransportDivider()
            ElapsedTimeText(isPaused: vm.state == .paused, elapsed: vm.formattedElapsed)
        }
    }

    @ViewBuilder
    private var screenSwitchButton: some View {
        if vm.settings.enabledSources.contains(.screen) {
            DockActionButton(
                title: "Screen",
                systemImage: BlitzSymbols.screen,
                help: "Change the recorded display or window without stopping"
            ) {
                showsScreenPicker = true
            }
            .popover(isPresented: $showsScreenPicker, arrowEdge: .bottom) {
                BlitzSourcePickerPopover(
                    model: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.canAdjustScreenCapture).model,
                    dismiss: { showsScreenPicker = false }
                )
            }
        }
    }

    private var savedExportURL: URL? {
        if forcesSavedChip { return vm.lastExportedURL }
        guard vm.state == .idle,
              vm.lastRecoveryOutput == nil,
              vm.canStartRecording else { return nil }
        return vm.lastExportedURL
    }
}

private struct TransportDivider: View {
    var body: some View {
        Rectangle()
            .fill(BlitzUI.selectedFill)
            .frame(width: 1, height: 26)
            .padding(.horizontal, 2)
    }
}

struct DockActionButton: View {
    let title: String
    let systemImage: String
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(BlitzType.captionEmphasis)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .pointingHandCursor()
        .help(help ?? title)
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
    vm.lastExportedURL = URL(fileURLWithPath: "/Volumes/harddrive/recordings/video-exa.mov")
    vm.lastExportedSourceTakeURL = URL(fileURLWithPath: "/Volumes/harddrive/recordings/sources/video-exa")
    vm.lastExportWarning = warning
    return vm
}

#Preview("Recording controls - compact") {
    let vm = bottomDockPreviewModel()
    vm.state = .recording
    return RecordingActionRow(vm: vm)
        .frame(width: 320)
        .padding(16)
        .background(BlitzUI.canvasBackground)
        .preferredColorScheme(.dark)
}

#Preview("Paused controls - compact") {
    let vm = bottomDockPreviewModel()
    vm.state = .paused
    return RecordingActionRow(vm: vm)
        .frame(width: 320)
        .padding(16)
        .background(BlitzUI.canvasBackground)
        .preferredColorScheme(.dark)
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
