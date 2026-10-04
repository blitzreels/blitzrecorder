import AppKit
import SwiftUI

@MainActor
final class RecordingHUDController {
    private let viewModel: RecorderViewModel
    private var panel: NSPanel?

    init(viewModel: RecorderViewModel) {
        self.viewModel = viewModel
    }

    func update(for state: RecordingState) {
        switch state {
        case .starting, .recording, .paused:
            show()
        case .idle, .finishing:
            panel?.orderOut(nil)
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else { return }
        if !panel.setFrameUsingName(Self.autosaveName) { placeAtTopCenter(panel) }
        panel.orderFrontRegardless()
    }

    private static let autosaveName = "RecordingHUD"

    private func makePanel() -> NSPanel {
        let controller = NSHostingController(rootView: RecordingHUDView(vm: viewModel))
        controller.sizingOptions = .preferredContentSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 48),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        panel.contentViewController = controller
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.sharingType = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setFrameAutosaveName(Self.autosaveName)
        return panel
    }

    private func placeAtTopCenter(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
    }
}

struct RecordingHUDView: View {
    @Bindable var vm: RecorderViewModel
    @AppStorage("recordingHUD.collapsed") private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                VStack(alignment: .leading, spacing: 14) {
                    if vm.currentScenes.count > 1 { scenes }
                    if vm.settings.enabledSources.contains(.screen) { screen }
                    if vm.settings.enabledSources.contains(.microphone) || vm.settings.enabledSources.contains(.systemAudio) {
                        audio
                    }
                }
                .padding(14)
            }
            if let notice = vm.autoSwitchNotice {
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                Label(notice, systemImage: "macwindow")
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.supportingText)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .transition(.opacity)
            } else if let suggestion = vm.suggestedScreenSource, vm.state == .recording {
                Rectangle().fill(BlitzUI.separator).frame(height: 1)
                switchPrompt(suggestion)
            }
        }
        .frame(width: isCollapsed ? nil : 400, alignment: .leading)
        .fixedSize()
        .background {
            RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous).fill(.black.opacity(0.55))
            RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous).fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius, style: .continuous)
                .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: BlitzUI.surfaceRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.18), value: isCollapsed)
        .animation(.easeOut(duration: 0.18), value: vm.suggestedScreenSource?.id)
        .animation(.easeOut(duration: 0.18), value: vm.autoSwitchNotice)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(BlitzType.glyph(11))
                .foregroundStyle(BlitzUI.tertiaryText)
                .frame(width: 14)
                .help("Drag to move")
                .accessibilityHidden(true)
            status
            if isCollapsed {
                if vm.settings.enabledSources.contains(.microphone) {
                    BlitzLevelMeter(levels: vm.micLevels, active: vm.state == .recording)
                        .frame(width: 56, height: 14)
                }
                if vm.currentScenes.count > 1 { sceneNumbers }
            }
            Spacer(minLength: 8)
            controls
            Button {
                isCollapsed.toggle()
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(BlitzType.glyph(10))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 24, height: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .help(isCollapsed ? "Show recording controls" : "Make the bar smaller")
            .accessibilityLabel(isCollapsed ? "Expand recording controls" : "Collapse recording controls")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 44)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    private var status: some View {
        HStack(spacing: 7) {
            switch vm.state {
            case .starting:
                ProgressView().controlSize(.mini)
                Text("Starting").foregroundStyle(BlitzUI.supportingText)
            case .paused:
                Image(systemName: "pause.fill")
                    .font(BlitzType.glyph(9))
                    .foregroundStyle(BlitzUI.warning)
                Text("Paused · \(vm.formattedElapsed)").foregroundStyle(BlitzUI.supportingText)
            default:
                RecordingHUDDot()
                Text(vm.formattedElapsed).foregroundStyle(BlitzUI.primaryText)
            }
        }
        .font(BlitzType.strong.monospacedDigit())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.state == .paused ? "Paused at \(vm.formattedElapsed)" : "Recording \(vm.formattedElapsed)")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(BlitzType.footnote)
            .foregroundStyle(BlitzUI.tertiaryText)
            .textCase(.uppercase)
    }

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Scene")
            RecorderSceneStrip(vm: vm)
        }
    }

    private var sceneNumbers: some View {
        HStack(spacing: 2) {
            ForEach(Array(vm.currentScenes.prefix(6).enumerated()), id: \.element.id) { index, scene in
                let isSelected = vm.selectedSceneID == scene.id
                Button {
                    vm.selectScene(scene.id)
                } label: {
                    Text("\(index + 1)")
                        .font(BlitzType.captionEmphasis.monospacedDigit())
                        .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(isSelected ? BlitzUI.strongFill : .clear, in: .rect(cornerRadius: BlitzUI.controlRadius))
                        .contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .disabled(!vm.canSwitchScene && !isSelected)
                .help(scene.name)
                .accessibilityLabel(scene.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var screen: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Screen")
            RecordingHUDSourceField(model: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.canAdjustScreenCapture).model)
            Toggle(isOn: $vm.followsActiveWindow) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Follow the window I'm using")
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.primaryText)
                    Text(vm.followsActiveWindow ? "Switches after 2 seconds in a new window" : "Asks before switching")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .toggleStyle(.blitzSwitch)
            .disabled(vm.settings.screenSourceBinding?.kind == .display)
            .help(vm.settings.screenSourceBinding?.kind == .display
                ? "You're recording a whole display, so every window is already in the video"
                : "Record whichever window you bring to the front")
        }
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Audio")
            if vm.settings.enabledSources.contains(.microphone) {
                RecordingHUDSourceField(model: MicrophoneSourcePickerModel(vm: vm, enabled: true).model)
                meterRow(.init(symbol: "mic.fill", title: "Mic", levels: vm.micLevels))
            }
            if vm.settings.enabledSources.contains(.systemAudio) {
                meterRow(.init(symbol: "speaker.wave.2.fill", title: "Mac", levels: vm.sysLevels))
            }
        }
    }

    private struct MeterRow {
        let symbol: String
        let title: String
        let levels: TrackLevels
    }

    private func meterRow(_ row: MeterRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.symbol)
                .font(BlitzType.glyph(10))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 14)
            Text(row.title)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 28, alignment: .leading)
            BlitzLevelMeter(levels: row.levels, active: vm.state == .recording)
                .frame(height: 16)
        }
        .accessibilityElement()
        .accessibilityLabel("\(row.title) level")
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: vm.togglePause) {
                Image(systemName: vm.state == .paused ? "play.fill" : "pause.fill")
                    .font(BlitzType.glyph(11))
                    .foregroundStyle(BlitzUI.primaryText)
                    .frame(width: 28, height: 28)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
                    .contentShape(.rect)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .disabled(vm.state != .recording && vm.state != .paused)
            .help(vm.state == .paused ? "Resume" : "Pause")
            .accessibilityLabel(vm.state == .paused ? "Resume" : "Pause")
            Button(action: vm.primaryAction) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white)
                        .frame(width: 9, height: 9)
                    if !isCollapsed {
                        Text("Stop").font(BlitzType.strong)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, isCollapsed ? 0 : 10)
                .frame(minWidth: 28, minHeight: 28)
                .background(BlitzUI.recordRed, in: .rect(cornerRadius: BlitzUI.controlRadius))
                .contentShape(.rect)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .disabled(vm.state != .recording && vm.state != .paused)
            .help("Stop recording")
            .accessibilityLabel("Stop recording")
        }
    }

    private func switchPrompt(_ suggestion: ScreenSourceBinding) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.badge.plus")
                .font(BlitzType.glyph(11))
                .foregroundStyle(BlitzUI.secondaryText)
            Text("Record \(suggestion.applicationName ?? suggestion.displayName) instead?")
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(1)
                .help(suggestion.displayName)
            Spacer(minLength: 8)
            Button("Switch", action: vm.acceptScreenSuggestion)
                .blitzButton(.secondary)
                .controlSize(.small)
            Button("Keep", action: vm.dismissScreenSuggestion)
                .blitzButton(.quiet)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .transition(.opacity)
    }
}

private struct RecordingHUDSourceField: View {
    let model: BlitzSourcePickerModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 16, height: 16)
                } else {
                    Image(systemName: model.systemImage)
                        .font(BlitzType.glyph(11))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 16)
                }
                Text(model.title)
                    .font(BlitzType.label)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(BlitzType.glyph(9))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPresented))
        .disabled(!model.enabled)
        .help(model.title)
        .accessibilityLabel(model.subtitle)
        .accessibilityValue(model.title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BlitzSourcePickerPopover(model: model) { isPresented = false }
                .preferredColorScheme(.dark)
        }
    }
}

private struct RecordingHUDDot: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(BlitzUI.recordRed)
            .frame(width: 8, height: 8)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
            }
            .accessibilityHidden(true)
    }
}
