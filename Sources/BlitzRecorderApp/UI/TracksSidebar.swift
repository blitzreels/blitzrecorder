import SwiftUI

struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sources")
                    .font(BlitzType.section)
                    .foregroundStyle(BlitzUI.primaryText)
                    .padding(.horizontal, 4)
                    .help("Every source that is on is recorded on its own track, even when a scene hides it.")

                VStack(spacing: 4) {
                    ForEach(displayedSources, id: \.self) { source in
                        deviceCard(for: source)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.automatic)
        .frame(minWidth: 216, idealWidth: 232, maxWidth: 232)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
    }

    private var displayedSources: [CaptureSource] {
        [.screen, .camera, .microphone, .systemAudio]
    }

    @ViewBuilder
    private func deviceCard(for source: CaptureSource) -> some View {
        switch source {
        case .screen:
            DeviceCard(
                source: .screen,
                title: "Screen",
                subtitle: vm.hasActiveScreenPickerSelection ? vm.selectedScreenSourceDisplayName : "Choose screen or window",
                status: sourceStatus(for: .screen),
                picker: ScreenCaptureSourcePickerModel(vm: vm, enabled: vm.isSourceConfigured(.screen)).model,
                levels: nil,
                vm: vm
            )
        case .camera:
            DeviceCard(
                source: .camera,
                title: "Camera",
                subtitle: vm.selectedCameraDisplayName,
                status: sourceStatus(for: .camera),
                picker: CameraSourcePickerModel(vm: vm, enabled: vm.isSourceConfigured(.camera)).model,
                levels: nil,
                vm: vm
            )
        case .microphone:
            DeviceCard(
                source: .microphone,
                title: "Microphone",
                subtitle: vm.selectedMicrophoneDisplayName,
                status: sourceStatus(for: .microphone),
                picker: MicrophoneSourcePickerModel(vm: vm, enabled: vm.isSourceConfigured(.microphone)).model,
                levels: vm.micLevels,
                vm: vm
            )
        case .systemAudio:
            DeviceCard(
                source: .systemAudio,
                title: "Mac audio",
                subtitle: "Sound from your apps",
                status: sourceStatus(for: .systemAudio),
                picker: nil,
                levels: vm.sysLevels,
                vm: vm
            )
        }
    }

    private func sourceStatus(for source: CaptureSource) -> SourceRowStatus {
        guard vm.isSourceConfigured(source) else {
            return SourceRowStatus(label: "Off", tone: .muted)
        }

        if source == .screen, let notice = vm.unavailableScreenSourceNotice {
            return SourceRowStatus(label: notice.title, tone: .warning)
        }

        if let recordingStatus = recordingStateStatus {
            return recordingStatus
        }

        if let notice = vm.sourceReadinessNotice(source) {
            return SourceRowStatus(label: notice.title, tone: .warning)
        }

        switch source {
        case .screen:
            if !vm.hasActiveScreenPickerSelection {
                return SourceRowStatus(label: "Choose screen or window", tone: .warning)
            }
            return SourceRowStatus(label: "Ready", tone: .active)
        case .camera:
            if vm.isRemoteCameraSelected {
                return remoteCameraStatus
            }
            return SourceRowStatus(label: "Ready", tone: .active)
        case .microphone, .systemAudio:
            return SourceRowStatus(label: "Ready", tone: .active)
        }
    }

    private var recordingStateStatus: SourceRowStatus? {
        switch vm.state {
        case .idle:
            return nil
        case .recording:
            return SourceRowStatus(label: "Live", tone: .active)
        case .paused:
            return SourceRowStatus(label: "Paused", tone: .muted)
        case .starting, .finishing:
            return SourceRowStatus(label: "Locked", tone: .muted)
        }
    }

    private var remoteCameraStatus: SourceRowStatus {
        let status = (vm.selectedRemoteCameraStatus ?? vm.selectedRemoteCameraReviewStatus).lowercased()
        if status.contains("waiting") || status.contains("disconnect") || status.contains("unavailable") {
            return SourceRowStatus(label: "Waiting", tone: .warning)
        }
        return SourceRowStatus(label: "iPhone", tone: .active)
    }

}

private struct DeviceCard: View {
    let source: CaptureSource
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    let picker: BlitzSourcePickerModel?
    let levels: TrackLevels?
    @Bindable var vm: RecorderViewModel
    @State private var isHovering = false
    @State private var showsPicker = false

    private var isSelected: Bool {
        guard let selected = vm.selectedSource?.source else { return false }
        return selected == source
    }
    private var isEnabled: Bool { vm.isSourceConfigured(source) }
    private var canPick: Bool { isEnabled && picker?.enabled == true }
    private var isPickerPresented: Binding<Bool> {
        source == .screen ? $vm.showsScreenSourcePicker : $showsPicker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    vm.selectSource(source)
                } label: {
                    HStack(spacing: 8) {
                        BlitzSymbol(configuration: .init(name: source.symbolName, size: 15))
                            .symbolVariant(isSelected && isEnabled ? .fill : .none)
                            .foregroundStyle(isSelected && isEnabled ? BlitzUI.mint : BlitzUI.secondaryText)
                            .frame(width: 20)
                        Text(title)
                            .font(BlitzType.label)
                            .foregroundStyle(isEnabled ? BlitzUI.primaryText : BlitzUI.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel("\(title), \(subtitle)")
                .accessibilityValue(status.label)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .help("\(title): \(status.label)")

                Toggle("Record \(title)", isOn: Binding(
                    get: { isEnabled },
                    set: { _ in vm.toggleSource(source) }
                ))
                .toggleStyle(.blitzCompactSwitch)
                .tint(BlitzUI.mint)
                .disabled(vm.state != .idle)
                .help(isEnabled ? "Stop recording \(title.lowercased())" : "Record \(title.lowercased())")
            }

            if isEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    if canPick {
                        pickerField
                    } else {
                        Text(subtitle)
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(1)
                    }
                    if let notice = vm.sourceReadinessNotice(source) {
                        DeviceReadinessNote(notice: notice, vm: vm)
                    } else if let note {
                        Text(note.text)
                            .font(BlitzType.caption)
                            .foregroundStyle(note.isWarning ? BlitzUI.warning : BlitzUI.tertiaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let levels {
                        BlitzLevelMeter(levels: levels, active: status.tone == .active)
                            .frame(height: 8)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected && isEnabled ? BlitzUI.selectedFill : (isHovering ? BlitzUI.quietFill : .clear),
            in: .rect(cornerRadius: BlitzUI.controlRadius)
        )
        .onHover { isHovering = $0 }
        .onChange(of: canPick) { if !canPick { isPickerPresented.wrappedValue = false } }
    }

    private var pickerField: some View {
        Button {
            vm.selectSource(source)
            isPickerPresented.wrappedValue = true
        } label: {
            HStack(spacing: 6) {
                if let icon = picker?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                }
                Text(subtitle)
                    .font(BlitzType.caption)
                    .foregroundStyle(source == .screen && vm.unavailableScreenSourceNotice != nil
                        ? BlitzUI.recordRed : BlitzUI.supportingText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(BlitzType.glyph(9))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BlitzMenuTriggerStyle(isPresented: isPickerPresented.wrappedValue))
        .accessibilityLabel("Choose \(title.lowercased())")
        .accessibilityValue(subtitle)
        .help(subtitle)
        .popover(isPresented: isPickerPresented, arrowEdge: .trailing) {
            if let picker {
                BlitzSourcePickerPopover(model: picker) { isPickerPresented.wrappedValue = false }
                    .preferredColorScheme(.dark)
            }
        }
    }

    private var note: (text: String, isWarning: Bool)? {
        if status.tone == .warning, status.label != subtitle { return (status.label, true) }
        if source == .screen || source == .camera, !vm.isSourceVisible(source) {
            return ("Hidden in this scene", false)
        }
        return nil
    }
}

private struct DeviceReadinessNote: View {
    let notice: SourceReadinessNotice
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if notice.isWaiting {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(BlitzType.glyph(9))
                        .accessibilityHidden(true)
                }
                Text(notice.title)
                    .font(BlitzType.captionEmphasis)
            }
            .foregroundStyle(notice.isWaiting ? BlitzUI.supportingText : notice.color)
            Text(notice.detail)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let action = notice.action {
                Button(action.title) { vm.resolveSourceReadiness(action) }
                    .blitzButton(.secondary)
                    .controlSize(.small)
                    .disabled(vm.isRequestingPermissions)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
    }
}

private struct SourceRowStatus: Equatable {
    let label: String
    let tone: SourceRowStatusTone
}

private enum SourceRowStatusTone: Equatable {
    case active
    case muted
    case warning
}

#if DEBUG
#Preview("Sources - Screen") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.screenSelected())
        .frame(height: 780)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Sources - Camera") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.cameraSelected())
        .frame(height: 780)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("Sources - Mic") {
    SourcesSidebar(vm: SourcesSidebarPreviewFactory.micSelected())
        .frame(height: 780)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

@MainActor
private enum SourcesSidebarPreviewFactory {
    static func screenSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.usesPickedScreenContent = true
        settings.selectedScenePreset = .screenTop50
        let vm = makeViewModel(settings: settings)
        vm.selectSource(.screen)
        return vm
    }

    static func cameraSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.selectedScenePreset = .cameraInset
        settings.selectedCameraID = "preview-camera"
        let vm = makeViewModel(settings: settings)
        vm.selectSource(.camera)
        return vm
    }

    static func micSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.camera]
        settings.selectedMicrophoneID = "preview-mic"
        let vm = makeViewModel(settings: settings)
        vm.selectSource(.microphone)
        return vm
    }

    private static var previewSettings: RecordingSettings {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone, .systemAudio]
        settings.hiddenSources = []
        settings.sceneLayout = SceneLayout.screenSplitLayout(
            screenHeight: SceneLayout.defaultScreenSplitHeight
        )
        settings.canvasBackgroundStyle = .graphite
        return settings
    }

    private static func makeViewModel(settings: RecordingSettings) -> RecorderViewModel {
        let suiteName = "BlitzRecorder.SourcesSidebarPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.settings = settings
        vm.availableDisplays = [
            SourceOption(id: "display-1", name: "Studio Display")
        ]
        vm.availableCameras = [
            SourceOption(id: "preview-camera", name: "FaceTime HD Camera")
        ]
        vm.availableMicrophones = [
            SourceOption(id: "preview-mic", name: "Studio Mic")
        ]
        vm.targetWindowInfo = TargetWindowInfo(
            appName: "Safari",
            windowTitle: "Landing Page",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        vm.targetWindowStatus = "Safari - Landing Page"
        previewLevels.forEach { vm.micLevels.append($0) }
        previewLevels.reversed().forEach { vm.sysLevels.append($0) }
        return vm
    }

    private static var previewLevels: [Float] {
        [0.12, 0.28, 0.42, 0.22, 0.68, 0.38, 0.52, 0.31, 0.74, 0.49, 0.26, 0.58]
    }
}
#endif
