import AppKit
import SwiftUI

struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                devicesHeader

                devicesSection

                Rectangle()
                    .fill(BlitzUI.separator)
                    .frame(height: 1)

                CaptureScenePicker(vm: vm)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.automatic)
        .frame(minWidth: 216, idealWidth: 232, maxWidth: 232)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
    }

    private var devicesHeader: some View {
        HStack {
            Text("Sources")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BlitzUI.primaryText)
            Spacer(minLength: 0)
            Text("Record")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
        }
        .padding(.horizontal, 2)
        .help("Enabled sources are recorded separately, even when hidden in a scene.")
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
        .help("Remove camera background after recording")
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
        vm.isRemoteCameraSelected ? "iphone.gen3" : BlitzSymbols.camera
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
                systemImage: BlitzSymbols.camera,
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
                systemImage: BlitzSymbols.camera,
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

private struct DeviceCard: View {
    let source: CaptureSource
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    var levels: TrackLevels?
    @Bindable var vm: RecorderViewModel
    @State private var isHovering = false

    private var isSelected: Bool { vm.selectedSource?.source == source }
    private var isEnabled: Bool { vm.isSourceConfigured(source) }

    var body: some View {
        header
            .background(
                isSelected && isEnabled ? BlitzUI.selectedFill : (isHovering ? BlitzUI.quietFill : .clear),
                in: .rect(cornerRadius: BlitzUI.controlRadius)
            )
            .opacity(isEnabled ? 1 : 0.62)
            .onHover { isHovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                vm.selectSource(source)
            } label: {
                HStack(spacing: 9) {
                    sourceIdentity

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BlitzUI.primaryText)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(BlitzUI.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if let levels {
                                Spacer(minLength: 0)
                                BlitzLevelMeter(levels: levels, active: status.tone == .active)
                                    .frame(width: 24, height: 10)
                                    .accessibilityHidden(true)
                            }
                        }

                        if let noticeLabel {
                            Text(noticeLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(detailColor)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel("\(title), \(subtitle)")
            .accessibilityValue(detailLabel)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .help("\(title): \(subtitle). \(detailLabel)")
            .pointingHandCursor()

            Toggle("Record \(title)", isOn: Binding(
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

    private var detailLabel: String {
        guard isEnabled, source == .screen || source == .camera else {
            return status.label
        }
        let sceneState = vm.isSourceVisible(source) ? "Visible in scene" : "Hidden from scene"
        return "\(status.label) · \(sceneState)"
    }

    private var noticeLabel: String? {
        if status.tone == .warning { return status.label }
        if isEnabled, source == .screen || source == .camera, !vm.isSourceVisible(source) {
            return "Hidden in scene"
        }
        return nil
    }

    private var detailColor: Color {
        status.tone == .warning ? BlitzUI.warning : .white.opacity(0.42)
    }

    private var sourceIdentity: some View {
        BlitzSymbol(configuration: .init(name: source.symbolName, size: 22))
            .foregroundStyle(isSelected && isEnabled ? BlitzUI.mint : BlitzUI.secondaryText)
            .frame(width: 28, height: 32)
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
                } else {
                    Button(action: vm.pickScreen) {
                        Label("Choose a window for vertical video", systemImage: "macwindow")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .blitzGlassButton()
                    ScreenContentModeControl(vm: vm, enabled: enabled)
                }
            }
        }
    }

    private var captureSourceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                title: "More App Windows…",
                subtitle: "Open the macOS picker for another window",
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
                systemImage: BlitzSymbols.screen,
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
                screenSourceSection((kind: .display, title: "Displays", group: .all)),
                screenSourceSection((kind: .application, title: "Suggested apps", group: .suggested)),
                screenSourceSection((kind: .application, title: "Apps", group: .standard)),
                screenSourceSection((kind: .window, title: "Windows", group: .standard))
            ] : [],
            actions: actions,
            layout: .thumbnails,
            enabled: enabled && vm.canAdjustScreenCapture,
            hiddenSections: vm.state == .idle ? [
                screenSourceSection((kind: .application, title: "Private apps", group: .sensitive)),
                screenSourceSection((kind: .window, title: "Private app windows", group: .sensitive))
            ] : []
        )
    }

    private func screenSourceSection(
        _ request: (
            kind: ScreenSourceBinding.Kind,
            title: String,
            group: ScreenSourcePickerGroup
        )
    ) -> BlitzSourcePickerSection {
        let options = vm.availableScreenSources.filter {
            $0.binding.kind == request.kind
                && (request.group == .all || $0.pickerPlacement.group == request.group)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            BlitzUI.sectionLabel("Framing", icon: "crop")

            SourceFramingPicker(selection: Binding(
                get: { vm.settings.screenContentMode },
                set: { vm.setScreenContentMode($0) }
            ), fitTitle: "Full display")
            .disabled(!enabled || !vm.canEditScene)

            if vm.settings.screenContentMode == .fill {
                Button {
                    vm.beginScreenCropMode()
                } label: {
                    Label("Adjust crop", systemImage: "crop")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .blitzGlassButton()
                .controlSize(.small)
                .disabled(!enabled || !vm.canEditScene)
                .pointingHandCursor()
                .help("Move and resize the visible screen area directly on the canvas")
            }
        }
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct ScreenSourceFramingControl: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if vm.hasAccessibilityAccessForWindowControls {
                    vm.fitCurrentScreenWindowToSlot()
                } else {
                    vm.requestAccessibilityForWindowControls()
                }
            } label: {
                Label("Fit window to scene", systemImage: "rectangle.arrowtriangle.2.inward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .blitzGlassButton()
            .help("Resize the selected window to this scene. Keep its full width and height visible.")

            Text("Keeps the whole window visible.")
                .font(.system(size: 10))
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("Screen size")
                Spacer(minLength: 0)
                Text("\(Int((vm.targetWindowZoom * 100).rounded()))%")
                    .monospacedDigit()
                Button(action: vm.resetTargetWindowZoom) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .blitzGlassButton()
                .accessibilityLabel("Reset screen size")
                .disabled(abs(vm.targetWindowZoom - 1) < 0.001)
            }
            .font(.system(size: 11, weight: .medium))

            Slider(
                value: Binding(
                    get: { Double(vm.targetWindowZoom) },
                    set: { vm.setTargetWindowZoom(CGFloat($0)) }
                ),
                in: 0.5...2,
                step: 0.05,
                onEditingChanged: { if !$0 { vm.applyTargetWindowZoom() } }
            )
            .controlSize(.small)
            .tint(BlitzUI.mint)
            .disabled(!vm.canShowScreenWindowFitControls)
            .accessibilityLabel("Screen size")
            .help("Resize the selected window. Larger content uses a smaller window, keeping the full window visible.")

            HStack {
                Text("More content")
                Spacer(minLength: 0)
                Text("Larger content")
            }
            .font(.system(size: 10))
            .foregroundStyle(BlitzUI.secondaryText)
        }
        .disabled(!enabled || !vm.canEditScene || vm.isScreenCropModeEnabled)
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
        VStack(alignment: .leading, spacing: 14) {
            if source == .microphone {
                MicrophoneSourceMenu(vm: vm, enabled: enabled)
            } else {
                HStack(spacing: 8) {
                    BlitzSymbol(configuration: .init(name: BlitzSymbols.systemAudio, size: 18))
                    Text("Mac audio")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(BlitzUI.secondaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(gainLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BlitzUI.primaryText)
                        .monospacedDigit()
                }

                TrackLevelGraph(levels: levels, active: enabled)
                    .frame(height: 22)
                    .opacity(enabled ? 1 : 0.3)
                    .accessibilityHidden(true)

                HStack(spacing: 7) {
                    BlitzSymbol(configuration: .init(name: "speaker", size: 16))
                    Slider(value: $gain, in: 0...2)
                        .controlSize(.small)
                        .tint(BlitzUI.mint)
                        .disabled(vm.state != .idle || !enabled)
                        .accessibilityLabel(source == .microphone ? "Microphone volume" : "System audio volume")
                        .accessibilityValue(gainLabel)
                    BlitzSymbol(configuration: .init(name: BlitzSymbols.systemAudio, size: 16))
                }
                .foregroundStyle(BlitzUI.secondaryText)
            }
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
    Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(enabled ? 0.38 : 0.24))
}

private struct MicrophoneSourceMenu: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        BlitzSourcePicker(model: pickerModel)
            .help("Choose microphone source")
    }

    private var pickerModel: BlitzSourcePickerModel {
        BlitzSourcePickerModel(
            title: vm.selectedMicrophoneDisplayName,
            subtitle: "Microphone input",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            sections: [BlitzSourcePickerSection(title: "Microphones", items: microphoneItems)],
            actions: [],
            layout: .list,
            enabled: enabled && vm.state != .starting && vm.state != .finishing
        )
    }

    private var microphoneItems: [BlitzSourcePickerItem] {
        let defaultItem = BlitzSourcePickerItem(
            title: "Default microphone",
            subtitle: "Follow the macOS default",
            systemImage: BlitzSymbols.microphone,
            icon: nil,
            thumbnail: nil,
            isSelected: vm.settings.selectedMicrophoneID == nil
        ) {
            vm.setMicrophone(nil)
        }
        return [defaultItem] + vm.availableMicrophones.map { option in
            BlitzSourcePickerItem(
                title: option.name,
                subtitle: nil,
                systemImage: BlitzSymbols.microphone,
                icon: nil,
                thumbnail: nil,
                isSelected: vm.settings.selectedMicrophoneID == option.id
            ) {
                vm.setMicrophone(option.id)
            }
        }
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
