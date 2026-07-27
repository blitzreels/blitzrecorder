import AppKit
import SwiftUI

struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                devicesHeader

                devicesSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .frame(minWidth: 236, idealWidth: 276, maxWidth: 276)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private var devicesHeader: some View {
        Text("Sources")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white.opacity(0.94))
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var devicesSection: some View {
        VStack(spacing: 6) {
            ForEach(displayedSources, id: \.self) { source in
                deviceCard(for: source)
            }
        }
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
                subtitle: vm.selectedScreenSourceDisplayName,
                status: sourceStatus(for: .screen),
                sourceIcon: selectedScreenSourceOption?.icon,
                vm: vm
            )
        case .camera:
            DeviceCard(
                source: .camera,
                title: "Camera",
                subtitle: vm.selectedCameraDisplayName,
                status: sourceStatus(for: .camera),
                vm: vm
            )
        case .microphone:
            DeviceCard(
                source: .microphone,
                title: "Microphone",
                subtitle: vm.selectedMicrophoneDisplayName,
                status: sourceStatus(for: .microphone),
                levels: vm.micLevels,
                vm: vm
            )
        case .systemAudio:
            DeviceCard(
                source: .systemAudio,
                title: "System audio",
                subtitle: "Mac audio",
                status: sourceStatus(for: .systemAudio),
                levels: vm.sysLevels,
                vm: vm
            )
        }
    }

    private var selectedScreenSourceOption: ScreenSourceOption? {
        guard !vm.settings.usesPickedScreenContent,
              let binding = vm.settings.screenSourceBinding else {
            return nil
        }
        return vm.availableScreenSources.first { $0.binding == binding }
    }

    private func sourceStatus(for source: CaptureSource) -> SourceRowStatus {
        guard vm.isSourceConfigured(source) else {
            return SourceRowStatus(label: "Off", tone: .muted)
        }

        if let recordingStatus = recordingStateStatus {
            return recordingStatus
        }

        if vm.recordingReadiness.blockers.contains(where: {
            $0.source == source && $0.permission == "Camera availability"
        }) {
            return SourceRowStatus(label: "Unavailable", tone: .warning)
        }

        if vm.recordingReadiness.blockers.contains(where: { $0.source == source }) {
            return SourceRowStatus(label: "No access", tone: .warning)
        }

        switch source {
        case .screen:
            if !vm.hasActiveScreenPickerSelection {
                return SourceRowStatus(label: "Choose", tone: .warning)
            }
            if vm.settings.usesPickedScreenContent {
                return SourceRowStatus(label: "Picked", tone: .active)
            }
            switch vm.settings.screenSourceBinding?.kind {
            case .application:
                return SourceRowStatus(label: "App", tone: .active)
            case .window:
                return SourceRowStatus(label: "Window", tone: .active)
            case .display, nil:
                return SourceRowStatus(label: "Display", tone: .active)
            }
        case .camera:
            if vm.isRemoteCameraSelected {
                return remoteCameraStatus
            }
            return SourceRowStatus(label: "Local", tone: .active)
        case .microphone:
            return SourceRowStatus(label: "Input", tone: .active)
        case .systemAudio:
            return SourceRowStatus(label: "System", tone: .active)
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

private struct TransparentWebcamToggle: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(iconOpacity))
                .frame(width: 18, height: 18)

            Text("Remove background")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(textOpacity))
                .lineLimit(1)

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { vm.settings.removesCameraBackgroundAfterRecording },
                set: { vm.setCameraBackgroundRemovalAfterRecording($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .contentShape(.rect(cornerRadius: 10))
        .disabled(vm.state != .idle || !enabled)
        .opacity(enabled ? 1 : 0.52)
        .onTapGesture {
            guard vm.state == .idle, enabled else { return }
            vm.setCameraBackgroundRemovalAfterRecording(!vm.settings.removesCameraBackgroundAfterRecording)
        }
        .pointingHandCursor()
        .help("Remove webcam background after recording")
    }

    private var iconOpacity: Double {
        guard enabled else { return 0.28 }
        return vm.settings.removesCameraBackgroundAfterRecording ? 0.82 : 0.45
    }

    private var textOpacity: Double {
        guard enabled else { return 0.3 }
        return vm.settings.removesCameraBackgroundAfterRecording ? 0.92 : 0.58
    }
}

private struct WebcamSourceMenu: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    private var selectedName: String {
        if vm.isRemoteCameraSelected {
            return vm.selectedRemoteCameraName ?? "Remote iPhone"
        }
        if let selectedCameraID = vm.settings.selectedCameraID,
           let option = vm.localCameraOptions.first(where: { $0.id == selectedCameraID }) {
            return option.name
        }
        return "Default camera"
    }

	var body: some View {
        BlitzSourcePicker(model: pickerModel)
        .help("Choose camera source")
    }

    private var selectedIcon: String {
        vm.isRemoteCameraSelected ? "iphone.gen3" : "video"
    }

    private var pickerModel: BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: selectedName,
            subtitle: vm.isRemoteCameraSelected ? "Wireless iPhone camera" : "Camera input",
            systemImage: selectedIcon,
            icon: nil,
            sections: cameraSections,
            actions: [
                BlitzSourcePickerItem(
                    title: "Find an iPhone",
                    subtitle: "Connect a wireless camera",
                    systemImage: "iphone.radiowaves.left.and.right",
                    icon: nil,
                    thumbnail: nil,
                    isSelected: false
                ) {
                    vm.startRemoteCameraDiscovery()
                }
            ],
            layout: .list,
            enabled: enabled && vm.state == .idle
        )
    }

    private var cameraSections: [BlitzSourcePickerSection] {
        var localItems = [
            BlitzSourcePickerItem(
                title: "Default camera",
                subtitle: "Follow the macOS default",
                systemImage: "video",
                icon: nil,
                thumbnail: nil,
                isSelected: vm.settings.selectedCameraID == nil
            ) {
                vm.setCamera(nil)
            }
        ]
        localItems += vm.localCameraOptions.map { option in
            BlitzSourcePickerItem(
                title: option.name,
                subtitle: "Connected to this Mac",
                systemImage: "video",
                icon: nil,
                thumbnail: nil,
                isSelected: vm.settings.selectedCameraID == option.id
            ) {
                vm.setCamera(option.id)
            }
        }

        let remoteItems = vm.remoteCameraOptions.map { option in
            BlitzSourcePickerItem(
                title: option.name,
                subtitle: "Wireless iPhone camera",
                systemImage: "iphone.gen3",
                icon: nil,
                thumbnail: nil,
                isSelected: vm.settings.selectedCameraID == option.id
            ) {
                vm.setCamera(option.id)
            }
        }

        return [
            BlitzSourcePickerSection(title: "This Mac", items: localItems),
            BlitzSourcePickerSection(title: "iPhone cameras", items: remoteItems)
        ]
    }
}

private struct BlitzMenuSelectorLabel: View {
    let title: String
    let icon: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.55 : 0.3))
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.42 : 0.24))
        }
        .foregroundStyle(.white.opacity(enabled ? 0.62 : 0.3))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DeviceCard: View {
    let source: CaptureSource
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    var sourceIcon: NSImage?
    var levels: TrackLevels?
    @Bindable var vm: RecorderViewModel

    private var isSelected: Bool { vm.selectedSource?.source == source }
    private var isEnabled: Bool { vm.isSourceConfigured(source) }

    var body: some View {
        header
        .blitzCard(cornerRadius: 10, selected: isSelected && isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .pointingHandCursor()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                vm.selectSource(source)
            } label: {
                HStack(spacing: 9) {
                    sourceIdentity

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)

                            BlitzStatusDot(tone: status.tone.statusTone)
                        }

                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)

                    if let levels {
                        BlitzLevelMeter(levels: levels, active: status.tone == .active)
                            .frame(width: 28, height: 14)
                    }

                    if isSelected && isEnabled {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in vm.toggleSource(source) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(vm.state != .idle)
            .tint(BlitzUI.mint)
            .frame(minWidth: 40, minHeight: 40)
            .help(isEnabled ? "Turn off \(title)" : "Turn on \(title)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .frame(minHeight: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sourceIdentity: some View {
        if let sourceIcon {
            Image(nsImage: sourceIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(.rect(cornerRadius: 5))
        } else {
            Image(systemName: source.symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(isSelected ? 0.82 : 0.48))
                .frame(width: 20, height: 20)
        }
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

    var statusTone: BlitzStatusTone {
        switch self {
        case .active: return .live
        case .muted: return .muted
        case .warning: return .warning
        }
    }
}

struct SelectedSourceInspector: View {
    @Bindable var vm: RecorderViewModel

    @ViewBuilder
    var body: some View {
        switch vm.selectedSource?.source ?? .screen {
        case .screen:
            ScreenSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.screen))
        case .camera:
            CameraSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.camera))
        case .microphone:
            AudioSourceInspector(
                title: "Input level",
                source: .microphone,
                levels: vm.micLevels,
                gain: Binding(
                    get: { vm.settings.microphoneGain },
                    set: { vm.setMicrophoneGain($0) }
                ),
                vm: vm
            )
        case .systemAudio:
            AudioSourceInspector(
                title: "Output level",
                source: .systemAudio,
                levels: vm.sysLevels,
                gain: Binding(
                    get: { vm.settings.systemAudioGain },
                    set: { vm.setSystemAudioGain($0) }
                ),
                vm: vm
            )
        }
    }
}

private struct ScreenSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            captureSourceRow
            if enabled && vm.hasActiveScreenPickerSelection {
                if vm.supportsScreenWindowScaling {
                    ScreenSourceFramingControl(vm: vm, enabled: enabled)
                }
                ScreenContentModeControl(vm: vm, enabled: enabled)
            }
        }
        .settingsPanelStyle()
    }

    private var captureSourceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            inspectorLabel("Source", enabled: enabled)

            BlitzSourcePicker(model: pickerModel)
            .help("Choose a display or window")
        }
    }

    private var captureSourceLabel: String {
        vm.selectedScreenSourceDisplayName
    }

    private var selectedScreenSourceIcon: NSImage? {
        selectedScreenSourceOption?.icon
    }

    private var selectedScreenSourceOption: ScreenSourceOption? {
        guard !vm.settings.usesPickedScreenContent,
              let binding = vm.settings.screenSourceBinding else {
            return nil
        }
        return vm.availableScreenSources.first { $0.binding == binding }
    }

    private var selectedScreenSourceSystemImage: String {
        if vm.settings.usesPickedScreenContent {
            return "rectangle.dashed"
        }

        switch vm.settings.screenSourceBinding?.kind {
        case .application:
            return "app"
        case .window:
            return "macwindow"
        case .display, nil:
            return "display"
        }
    }

    private var pickerModel: BlitzSourcePickerModel {
        let actions = [
            BlitzSourcePickerItem(
                title: "Choose App Window",
                subtitle: "Fits the window to this scene automatically",
                systemImage: "rectangle.dashed",
                icon: nil,
                thumbnail: nil,
                isSelected: vm.activePickedScreenContentKind == .application
                    || vm.activePickedScreenContentKind == .window
            ) {
                vm.pickScreen()
            },
            BlitzSourcePickerItem(
                title: "Pick Full Screen",
                subtitle: "Records an entire display without resizing apps",
                systemImage: "display",
                icon: nil,
                thumbnail: nil,
                isSelected: vm.activePickedScreenContentKind == .display
            ) {
                vm.pickFullScreen()
            }
        ]

        return BlitzSourcePickerModel(
            title: captureSourceLabel,
            subtitle: selectedScreenSourceKindLabel,
            systemImage: selectedScreenSourceSystemImage,
            icon: selectedScreenSourceIcon,
            sections: vm.state == .idle ? [
                screenSourceSection((kind: .display, title: "Displays")),
                screenSourceSection((kind: .application, title: "Apps")),
                screenSourceSection((kind: .window, title: "Windows"))
            ] : [],
            actions: actions,
            layout: .thumbnails,
            enabled: enabled && vm.canAdjustScreenCapture
        )
    }

    private func screenSourceSection(
        _ request: (kind: ScreenSourceBinding.Kind, title: String)
    ) -> BlitzSourcePickerSection {
        let options = vm.availableScreenSources.filter { $0.binding.kind == request.kind }
        return BlitzSourcePickerSection(
            title: request.title,
            items: options.map { option in
                BlitzSourcePickerItem(
                    title: option.title,
                    subtitle: option.subtitle,
                    systemImage: option.systemImage,
                    icon: option.icon,
                    thumbnail: vm.screenSourceThumbnails[option.id],
                    isSelected: !vm.settings.usesPickedScreenContent
                        && vm.settings.screenSourceBinding == option.binding
                ) {
                    vm.setScreenSource(option.binding)
                }
            }
        )
    }

    private var selectedScreenSourceKindLabel: String {
        if !vm.hasActiveScreenPickerSelection {
            return "Picker selection required"
        }
        if vm.settings.usesPickedScreenContent {
            return "Screen capture"
        }
        switch vm.settings.screenSourceBinding?.kind {
        case .application:
            return "App window capture"
        case .window:
            return "Window capture"
        case .display, nil:
            return "Display capture"
        }
    }
}

struct ScreenContentModeControl: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            inspectorLabel("Screen framing", enabled: enabled)

            HStack(spacing: 7) {
                modeButton(.fill, title: "Fill frame", detail: "Crop edges")
                modeButton(.fit, title: "Show all", detail: "No crop")
            }

            if vm.settings.screenContentMode == .fill {
                Button {
                    vm.beginScreenCropMode()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "crop")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Adjust crop")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("Choose which part stays visible")
                                .font(.system(size: 8.5, weight: .medium))
                                .opacity(0.58)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .contentShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .background(BlitzUI.controlFill, in: .rect(cornerRadius: 8))
                .disabled(!enabled || !vm.canEditScene)
                .pointingHandCursor()
                .help("Move and resize the visible screen area directly on the canvas")
            }
        }
        .opacity(enabled ? 1 : 0.55)
    }

    private func modeButton(
        _ mode: CameraContentMode,
        title: String,
        detail: String
    ) -> some View {
        let selected = vm.settings.screenContentMode == mode
        return Button {
            vm.setScreenContentMode(mode)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 17)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .bold))
                    Text(detail)
                        .font(.system(size: 8.5, weight: .medium))
                        .opacity(0.58)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? BlitzUI.mint : .white.opacity(0.78))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 43)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(
            selected ? BlitzUI.mint.opacity(0.12) : BlitzUI.controlFill,
            in: .rect(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? BlitzUI.mint.opacity(0.72) : .white.opacity(0.08), lineWidth: 1)
        }
        .disabled(!enabled || !vm.canEditScene)
        .pointingHandCursor()
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .help(mode == .fill
            ? "Fill the entire frame. Source edges can be cropped."
            : "Keep the entire source visible without cropping.")
    }
}

private struct ScreenSourceFramingControl: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    @ViewBuilder
    var body: some View {
        if vm.supportsScreenWindowScaling {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Make UI larger")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.38))

                    Spacer(minLength: 0)

                    Text("\(Int((vm.targetWindowZoom * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.32))
                }

                Slider(
                    value: Binding(
                        get: { Double(vm.targetWindowZoom) },
                        set: { vm.setTargetWindowZoom(CGFloat($0)) }
                    ),
                    in: ScreenSourceZoomGeometry.minimumZoom...ScreenSourceZoomGeometry.maximumZoom,
                    step: 0.05,
                    onEditingChanged: { editing in
                        if !editing {
                            vm.applyTargetWindowZoom()
                        }
                    }
                )
                .controlSize(.small)
                .tint(BlitzUI.mint)
                .disabled(!canUseWindowControls)
                .help("Resize and reflow the source window while keeping its complete UI visible")

                HStack(spacing: 8) {
                    Text("Normal")
                    Spacer(minLength: 0)
                    Button {
                        vm.resetTargetWindowZoom()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 9)
                            .frame(minHeight: 26)
                            .contentShape(.rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(canUseWindowControls ? 0.78 : 0.3))
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 1)
                    }
                    .disabled(!canUseWindowControls || abs(vm.targetWindowZoom - 1) < 0.001)
                    .pointingHandCursor()
                    Spacer(minLength: 0)
                    Text("2× larger")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.4 : 0.22))

                if vm.canShowScreenWindowFitControls {
                    windowFitControl
                } else {
                    enableWindowFitButton
                }
            }
            .opacity(enabled ? 1 : 0.55)
        }
    }

    private var windowFitControl: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                vm.fitCurrentScreenWindowToSlot()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.arrowtriangle.2.inward")
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Fit full window")
                            .font(.system(size: 11, weight: .bold))
                        Text("Full width + height, no crop")
                            .font(.system(size: 9, weight: .medium))
                            .opacity(0.58)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .background(BlitzUI.mint.opacity(0.12), in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(BlitzUI.mint.opacity(0.48), lineWidth: 1)
            }
            .disabled(!canUseWindowControls)
            .pointingHandCursor()
            .help("Resize and reflow the complete source window inside its canvas frame")
        }
    }

    private var enableWindowFitButton: some View {
        Button {
            vm.requestAccessibilityForWindowControls()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "lock.open")
                    .font(.system(size: 9, weight: .semibold))
                Text("Enable window fit")
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(BlitzUI.mint.opacity(enabled ? 0.82 : 0.3))
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 9))
        }
        .blitzGlassButton()
        .disabled(!enabled || !vm.canAdjustScreenCapture)
        .help("Open the Accessibility guide for window fitting")
    }

    private var canUseWindowControls: Bool {
        enabled && vm.canAdjustScreenCapture && vm.canShowScreenWindowFitControls
    }
}

private struct CameraSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WebcamSourceMenu(vm: vm, enabled: enabled)
            if vm.isRemoteCameraSelected {
                remoteCameraSettingsShortcut
            }
            TransparentWebcamToggle(vm: vm, enabled: enabled)
        }
        .settingsPanelStyle()
    }

    private var remoteCameraSettingsShortcut: some View {
        Button {
            vm.onPresentSettings?(.devices)
        } label: {
            HStack(spacing: 8) {
                inspectorIcon("slider.horizontal.3", enabled: enabled)

                VStack(alignment: .leading, spacing: 1) {
                    Text("iPhone settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.38))
                        .lineLimit(1)
                    Text("Change camera controls in Settings (Cmd+,).")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(enabled ? 0.55 : 0.3))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(enabled ? 0.42 : 0.24))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 8))
        }
        .blitzGlassButton()
        .controlSize(.small)
        .disabled(!enabled)
        .pointingHandCursor()
        .help("Open iPhone camera settings. You can also use Cmd+, then Devices.")
    }
}

private struct AudioSourceInspector: View {
    let title: String
    let source: CaptureSource
    let levels: TrackLevels
    @Binding var gain: Double
    @Bindable var vm: RecorderViewModel

    private var enabled: Bool { vm.settings.enabledSources.contains(source) }
    private var gainLabel: String { "\(Int((gain * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.38))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(gainLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }

            if source == .microphone {
                MicrophoneSourceMenu(vm: vm, enabled: enabled)
            } else {
                InspectorMetricRow(
                    icon: "speaker.wave.2",
                    title: "Selected",
                    value: "Mac audio",
                    enabled: enabled
                )
            }

            TrackLevelGraph(levels: levels, active: enabled)
                .frame(height: 22)
                .opacity(enabled ? 1 : 0.3)

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Slider(value: $gain, in: 0...2)
                    .controlSize(.mini)
                    .disabled(vm.state != .idle || !enabled)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .settingsPanelStyle()
    }
}

private struct InspectorMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            inspectorIcon(icon, enabled: enabled)

            VStack(alignment: .leading, spacing: 1) {
                inspectorLabel(title, enabled: enabled)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
    }
}

private func inspectorIcon(_ icon: String, enabled: Bool) -> some View {
    Image(systemName: icon)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(enabled ? 0.5 : 0.28))
        .frame(width: 20, height: 20)
        .background(.white.opacity(enabled ? 0.07 : 0.035), in: .rect(cornerRadius: 6))
}

private func inspectorLabel(_ title: String, enabled: Bool) -> some View {
    Text(title.uppercased())
        .font(.system(size: 9, weight: .heavy))
        .tracking(0.5)
        .foregroundStyle(.white.opacity(enabled ? 0.38 : 0.24))
}

private struct MicrophoneSourceMenu: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        BlitzGlassMenu(entries: entries, menuWidth: 260) {
            BlitzMenuSelectorLabel(title: vm.selectedMicrophoneDisplayName, icon: "mic", enabled: enabled)
        }
        .controlSize(.small)
        .disabled(vm.state != .idle)
        .pointingHandCursor()
        .help("Choose microphone source")
    }

    private var entries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(BlitzMenuItem(
                title: "Default microphone",
                systemImage: "mic",
                isSelected: vm.settings.selectedMicrophoneID == nil
            ) {
                vm.setMicrophone(nil)
            })
        ]

        if !vm.availableMicrophones.isEmpty {
            entries.append(.divider)
            for option in vm.availableMicrophones {
                entries.append(.item(BlitzMenuItem(
                    title: option.name,
                    systemImage: "mic",
                    isSelected: vm.settings.selectedMicrophoneID == option.id
                ) {
                    vm.setMicrophone(option.id)
                }))
            }
        }

        return entries
    }
}

private extension View {
    func settingsPanelStyle() -> some View {
        self
    }
}

private struct EmptySourceHint: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }
}

private struct TrackLevelGraph: View {
    let levels: TrackLevels
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let values = levels.levels
            guard !values.isEmpty else { return }

            let recentMax = max(0.08, (values.suffix(16).max() ?? 0) * 0.86)
            let barCount = values.count
            let spacing: CGFloat = 1
            let barWidth = max(1.5, (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            let centerY = size.height / 2
            let color = BlitzUI.levelColor(active: active)

            for (i, raw) in values.enumerated() {
                let normalized = raw > 0.003 ? max(0.04, min(1, raw / recentMax)) : 0.02
                let h = max(1.5, CGFloat(normalized) * size.height)
                let x = CGFloat(i) * (barWidth + spacing)
                let rect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
                let alpha = 0.25 + 0.7 * CGFloat(normalized)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(color.opacity(alpha))
                )
            }
        }
    }
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
