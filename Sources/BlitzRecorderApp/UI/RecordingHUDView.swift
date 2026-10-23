import AppKit
import SwiftUI

struct RecordingHUDActions {
    let resize: (CGSize) -> Void
    let dragChanged: () -> Void
    let dragEnded: () -> Void
}

struct RecordingHUDView: View {
    @Bindable var vm: RecorderViewModel
    @Bindable var model: RecordingHUDModel
    let actions: RecordingHUDActions
    @State private var isDragHovering = false
    @State private var isIdle = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var idleTask: Task<Void, Never>?

    private var hasPrompt: Bool {
        vm.unavailableScreenSourceNotice != nil || vm.screenSource.autoSwitchNotice != nil
            || (vm.screenSource.suggestedScreenSource != nil && vm.state == .recording)
    }

    private var isWide: Bool { model.isExpanded || hasPrompt }
    private static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            if model.anchor.isBottom {
                if model.isExpanded { details; divider }
                prompt
                bar
            } else {
                bar
                prompt
                if model.isExpanded { divider; details }
            }
        }
        .frame(width: Self.width)
        .fixedSize()
        .background(RecordingHUDSurface())
        .opacity(isIdle && !isWide ? 0.5 : 1)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { actions.resize($0) }
        .onHover(perform: hover)
        .onChange(of: model.isDragging) { _, dragging in
            if dragging {
                collapseTask?.cancel()
                idleTask?.cancel()
                isIdle = false
            }
        }
        .onAppear(perform: scheduleIdle)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.18, bounce: 0), value: model.isExpanded)
        .animation(.easeOut(duration: 0.18), value: hasPrompt)
        .animation(.easeOut(duration: 0.18), value: isIdle)
    }

    private func hover(_ hovering: Bool) {
        guard !model.isDragging else { return }
        collapseTask?.cancel()
        idleTask?.cancel()
        isIdle = false
        if hovering {
            model.isHovering = true
            return
        }
        collapseTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            model.isHovering = false
            scheduleIdle()
        }
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !model.isHovering else { return }
            isIdle = true
        }
    }

    private var divider: some View {
        Rectangle().fill(BlitzUI.hoverFill).frame(height: 1).padding(.horizontal, 12)
    }

    private var bar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 10) {
                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 3) {
                            Circle().frame(width: 3, height: 3)
                            Circle().frame(width: 3, height: 3)
                        }
                    }
                }
                .frame(width: 12, height: 18)
                .foregroundStyle(isDragHovering ? BlitzUI.primaryText : BlitzUI.secondaryText)
                .accessibilityHidden(true)
                status
                if vm.settings.enabledSources.contains(.microphone) {
                    RecordingHUDMeter(levels: vm.micLevels, isActive: vm.state == .recording)
                        .help(vm.selectedMicrophoneDisplayName)
                }
                RecorderVisibilityIndicator(hidden: !vm.settings.includesRecorderUI)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(isDragHovering || model.isDragging ? BlitzUI.hoverFill : BlitzUI.quietFill, in: .capsule)
            .contentShape(.capsule)
            .gesture(WindowDragGesture()
                .onChanged { _ in actions.dragChanged() }
                .onEnded { _ in actions.dragEnded() })
            .allowsWindowActivationEvents(true)
            .blitzCursor(model.isDragging ? .closedHand : .openHand)
            .onHover { isDragHovering = $0 }
            .help("Drag to move recording controls")
            Image(systemName: model.anchor.isBottom ? "chevron.up" : "chevron.down")
                .font(BlitzType.symbol(9))
                .foregroundStyle(BlitzUI.tertiaryText)
                .padding(.horizontal, 4)
                .opacity(isWide ? 0 : 1)
                .accessibilityHidden(true)
            controls
        }
        .padding(.leading, 4)
        .padding(.trailing, 5)
        .frame(height: 40)
        .help(model.isExpanded ? "Drag to move" : "Hover to change scene, screen and mic. Drag to move.")
    }

    private var status: some View {
        HStack(spacing: 7) {
            switch vm.state {
            case .starting:
                ProgressView().controlSize(.mini)
                Text("Starting").foregroundStyle(BlitzUI.supportingText)
            case .paused:
                Image(systemName: "pause.fill")
                    .font(BlitzType.symbol(9))
                    .foregroundStyle(BlitzUI.warning)
                Text(vm.formattedElapsed).foregroundStyle(BlitzUI.supportingText)
            default:
                RecordingHUDDot()
                Text(vm.formattedElapsed).foregroundStyle(BlitzUI.primaryText)
            }
        }
        .font(BlitzType.section.monospacedDigit())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.state == .paused ? "Paused at \(vm.formattedElapsed)" : "Recording \(vm.formattedElapsed)")
    }

    private var controls: some View {
        HStack(spacing: 2) {
            RecordingHUDIconButton(configuration: .init(
                symbol: vm.state == .paused ? "play.fill" : "pause.fill",
                fill: .clear,
                help: vm.state == .paused ? "Resume" : "Pause",
                isEnabled: vm.state == .recording || vm.state == .paused,
                action: vm.togglePause
            ))
            RecordingHUDIconButton(configuration: .init(
                symbol: "stop.fill", fill: BlitzUI.recordRed,
                help: "Stop recording",
                isEnabled: vm.state == .recording || vm.state == .paused,
                action: vm.primaryAction
            ))
        }
    }

    @ViewBuilder
    private var prompt: some View {
        if let missing = vm.unavailableScreenSourceNotice {
            promptRow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BlitzUI.recordRed)
                VStack(alignment: .leading, spacing: 4) {
                    Text(missing.title).foregroundStyle(BlitzUI.recordRed)
                    Text(missing.detail).foregroundStyle(BlitzUI.secondaryText)
                        .font(BlitzType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    BlitzSourcePicker(model: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.canAdjustScreenCapture).model)
                }
            }
        }
        if let notice = vm.screenSource.autoSwitchNotice {
            promptRow {
                RecordingSourceAppIcon(binding: notice)
                    .frame(width: 24, height: 24)
                Text("Switching to \(notice.applicationName ?? notice.displayName)…")
                    .foregroundStyle(BlitzUI.primaryText).lineLimit(1)
                Spacer(minLength: 0)
            }
        } else if let suggestion = vm.screenSource.suggestedScreenSource, vm.state == .recording {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Label("This window isn’t being recorded", systemImage: "exclamationmark.triangle.fill")
                        .font(BlitzType.section)
                        .foregroundStyle(BlitzUI.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    if let current = vm.settings.screenSourceBinding {
                        Text("Still recording: \(current.displayName)")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.primaryText)
                            .lineLimit(2)
                            .help(current.displayName)
                    }
                    HStack(spacing: 8) {
                        RecordingSourceAppIcon(binding: suggestion)
                            .frame(width: 32, height: 32)
                        Text(suggestion.displayName)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(2)
                            .help(suggestion.displayName)
                    }
                    HStack {
                        Button("Keep current", action: vm.dismissScreenSuggestion)
                            .blitzButton(.quiet)
                        Spacer(minLength: 8)
                        Button("Switch to this window", action: vm.acceptScreenSuggestion)
                            .blitzButton(.accent)
                    }
                    .controlSize(.regular)
                }
            }
            .font(BlitzType.label)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlitzUI.warning.opacity(0.1), in: .rect(cornerRadius: BlitzUI.surfaceRadius, style: .continuous))
            .padding(4)
            .transition(.opacity)
        }
    }

    private func promptRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(BlitzType.label)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isPeeking {
                Text("Hover the bar anytime to change scene, screen and mic.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            if vm.currentScenes.count > 1 { scenes }
            VStack(spacing: 2) {
                if vm.settings.enabledSources.contains(.screen) {
                    RecordingHUDPickerRow(configuration: .init(
                        symbol: vm.settings.screenSourceBinding?.kind == .display ? "display" : "macwindow",
                        title: "Screen",
                        model: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.canAdjustScreenCapture).model,
                        openPopovers: $model.openPopovers
                    ))
                    followRow
                }
                if vm.settings.enabledSources.contains(.microphone) {
                    RecordingHUDPickerRow(configuration: .init(
                        symbol: "mic.fill", title: "Microphone",
                        model: MicrophoneSourcePickerModel(vm: vm, enabled: true).model,
                        openPopovers: $model.openPopovers
                    ))
                }
            }
        }
        .padding(12)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: model.anchor.isBottom ? .bottom : .top)))
    }

    private var scenes: some View {
        HStack(spacing: 6) {
            ForEach(vm.currentScenes.prefix(4)) { scene in
                let isSelected = vm.selectedSceneID == scene.id
                Button {
                    vm.selectScene(scene.id)
                } label: {
                    VStack(spacing: 5) {
                        BlitzSceneLayoutThumbnail(
                            layout: scene.layout,
                            sceneLayout: vm.sceneLayout(scene),
                            visibleSources: vm.sceneVisibleSources(scene)
                        )
                        .frame(height: 36)
                        Text(vm.sceneLabel(scene))
                            .font(BlitzType.footnote)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius)
                        } else {
                            RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous).fill(BlitzUI.quietFill)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .disabled(!vm.canSwitchScene && !isSelected)
                .help(vm.sceneLabel(scene))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var followRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.swap")
                .font(BlitzType.symbol(12))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 20)
            Text("Follow active window")
                .font(BlitzType.label)
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 8)
            Toggle("Follow active window", isOn: $vm.followsActiveWindow)
                .toggleStyle(.blitzSwitchOnly)
                .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .disabled(vm.settings.screenSourceBinding?.kind == .display)
        .help(vm.settings.screenSourceBinding?.kind == .display
            ? "You're recording a whole display, so every window is already in the video"
            : "On: switch and fit the active window automatically. Off: ask before switching.")
    }
}

/// Circular corners, not continuous: the bar's ends must be true half circles so the round stop button sits
/// concentric in them.
private struct RecordingHUDSurface: View {
    private let shape = RoundedRectangle(cornerRadius: 20, style: .circular)

    var body: some View {
        shape
            .fill(.regularMaterial)
            .overlay { shape.fill(BlitzUI.glassTint) }
            .overlay { BlitzEdgeHighlight(shape: shape) }
    }
}

private struct RecordingSourceAppIcon: View {
    let binding: ScreenSourceBinding

    var body: some View {
        Group {
            if let icon = ScreenSourceCatalog.appIcon(for: binding) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: binding.kind == .display ? "display" : "macwindow")
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .accessibilityHidden(true)
    }
}
