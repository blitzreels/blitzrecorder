import SwiftUI

struct SourcesSidebar: View {
    @Bindable var vm: RecorderViewModel

    /// Which device cards are expanded. Hoisted here (instead of living inside each
    /// `DeviceCard`) so the sidebar can drop `.draggable` from a card while it's open —
    /// otherwise the reorder drag fights the sliders/menus inside the expanded body.
    @State private var expandedSources: Set<CaptureSource> = []

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
        HStack(spacing: 8) {
            Text("Devices")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))

            Spacer(minLength: 0)

            if !inactiveSources.isEmpty {
                BlitzGlassMenu(
                    entries: inactiveSources.map { source in
                        .item(BlitzMenuItem(title: source.shortLabel, systemImage: source.symbolName) {
                            vm.toggleSource(source)
                        })
                    },
                    menuWidth: 200
                ) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .controlSize(.small)
                .disabled(vm.state != .idle)
                .pointingHandCursor()
                .help("Add a device")
            }
        }
        .padding(.horizontal, 2)
    }

    private var devicesSection: some View {
        VStack(spacing: 8) {
            if shownSources.isEmpty {
                EmptySourceHint(title: "No devices yet. Use + to add one.")
            }
            ForEach(shownVideoOrder, id: \.self) { kind in
                let source = captureSource(for: kind)
                Group {
                    // Only collapsed cards are draggable — an expanded card holds
                    // interactive controls (camera menu, screen crop) that the drag would hijack.
                    if expandedSources.contains(source) {
                        deviceCard(for: source)
                    } else {
                        deviceCard(for: source)
                            .draggable(kind.rawValue) {
                                deviceCard(for: source).opacity(0.85)
                            }
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    return handleDrop(items, onto: kind)
                }
            }
            ForEach(shownAudioSources, id: \.self) { source in
                deviceCard(for: source)
            }
        }
    }

    @ViewBuilder
    private func deviceCard(for source: CaptureSource) -> some View {
        switch source {
        case .screen:
            DeviceCard(
                source: .screen,
                title: "Screen",
                subtitle: vm.screenCropLabel,
                status: sourceStatus(for: .screen),
                isExpanded: expansionBinding(for: .screen),
                vm: vm
            )
        case .camera:
            DeviceCard(
                source: .camera,
                title: "Camera",
                subtitle: vm.selectedCameraDisplayName,
                status: sourceStatus(for: .camera),
                isExpanded: expansionBinding(for: .camera),
                vm: vm
            )
        case .microphone:
            DeviceCard(
                source: .microphone,
                title: "Mic",
                subtitle: vm.selectedMicrophoneDisplayName,
                status: sourceStatus(for: .microphone),
                isExpanded: expansionBinding(for: .microphone),
                levels: vm.micLevels,
                vm: vm
            )
        case .systemAudio:
            DeviceCard(
                source: .systemAudio,
                title: "System",
                subtitle: "Mac audio",
                status: sourceStatus(for: .systemAudio),
                isExpanded: expansionBinding(for: .systemAudio),
                levels: vm.sysLevels,
                vm: vm
            )
        }
    }

    private func expansionBinding(for source: CaptureSource) -> Binding<Bool> {
        Binding(
            get: { expandedSources.contains(source) },
            set: { isOpen in
                if isOpen {
                    expandedSources.insert(source)
                } else {
                    expandedSources.remove(source)
                }
            }
        )
    }

    private var shownSources: [CaptureSource] {
        shownVideoOrder.map(captureSource(for:)) + shownAudioSources
    }

    private var shownVideoOrder: [SceneLayerKind] {
        SceneLayoutProjection.frontToBackOrder(for: vm.settings.sceneLayout)
            .filter { vm.isSourceConfigured(captureSource(for: $0)) }
    }

    private var shownAudioSources: [CaptureSource] {
        [.microphone, .systemAudio].filter { vm.isSourceConfigured($0) }
    }

    private var inactiveSources: [CaptureSource] {
        [
            CaptureSource.screen,
            .camera,
            .microphone,
            .systemAudio
        ].filter { !vm.isSourceConfigured($0) }
    }

    private func handleDrop(_ items: [String], onto target: SceneLayerKind) -> Bool {
        guard vm.canEditScene else { return false }
        guard let raw = items.first,
              let dropped = SceneLayerKind(rawValue: raw),
              dropped != target else { return false }

        guard let order = SceneLayoutProjection.reorderedBackToFrontOrder(
            moving: dropped,
            onto: target,
            in: vm.settings.sceneLayout
        ) else { return false }

        vm.setSceneLayerOrder(order)
        return true
    }

    private func captureSource(for kind: SceneLayerKind) -> CaptureSource {
        switch kind {
        case .screen:
            return .screen
        case .camera:
            return .camera
        }
    }

    private func sourceStatus(for source: CaptureSource) -> SourceRowStatus {
        if let recordingStatus = recordingStateStatus {
            return recordingStatus
        }

        if vm.recordingReadiness.blockers.contains(where: { $0.source == source }) {
            return SourceRowStatus(label: "No access", tone: .warning)
        }

        switch source {
        case .screen:
            if vm.settings.usesPickedScreenContent {
                return SourceRowStatus(label: "Picked", tone: .active)
            }
            return SourceRowStatus(label: "Display", tone: .active)
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
        BlitzGlassMenu(entries: entries, menuWidth: 260) {
            BlitzMenuSelectorLabel(title: selectedName, icon: selectedIcon, enabled: enabled)
        }
        .controlSize(.small)
        .disabled(vm.state != .idle)
        .pointingHandCursor()
        .help("Choose camera source")
    }

    private var selectedIcon: String {
        vm.isRemoteCameraSelected ? "iphone.gen3" : "video"
    }

    private var entries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = [
            .item(BlitzMenuItem(title: "Detect iPhone Camera", systemImage: "iphone.radiowaves.left.and.right") {
                vm.startRemoteCameraDiscovery()
            }),
            .divider,
            .item(BlitzMenuItem(
                title: "Default camera",
                systemImage: "video",
                isSelected: vm.settings.selectedCameraID == nil
            ) {
                vm.setCamera(nil)
            })
        ]

        if !vm.remoteCameraOptions.isEmpty {
            entries.append(.divider)
            for option in vm.remoteCameraOptions {
                entries.append(.item(BlitzMenuItem(
                    title: option.name,
                    systemImage: "iphone.gen3",
                    isSelected: vm.settings.selectedCameraID == option.id
                ) {
                    vm.setCamera(option.id)
                }))
            }
        }

        if !vm.localCameraOptions.isEmpty {
            entries.append(.divider)
            for option in vm.localCameraOptions {
                entries.append(.item(BlitzMenuItem(
                    title: option.name,
                    systemImage: "video",
                    isSelected: vm.settings.selectedCameraID == option.id
                ) {
                    vm.setCamera(option.id)
                }))
            }
        }

        return entries
    }
}

/// Shared trigger label for the device selector dropdowns: an icon, the selected
/// device name, and a chevron — styled to read as one of our glass selectors.
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

/// A C-style expandable glass device card. The header is the selection mechanism
/// (tap selects the source and toggles the expanded inspector body). No on/off
/// toggle — being listed means connected.
private struct DeviceCard: View {
    let source: CaptureSource
    let title: String
    let subtitle: String
    let status: SourceRowStatus
    @Binding var isExpanded: Bool
    var levels: TrackLevels?
    @Bindable var vm: RecorderViewModel

    private var isSelected: Bool { vm.selectedSource?.source == source }
    private var isVideoSource: Bool { source == .screen || source == .camera }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider()
                    .overlay(BlitzUI.separator)
                    .padding(.horizontal, 12)

                expandedBody
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
        }
        .blitzCard(cornerRadius: 10, selected: isSelected)
        .pointingHandCursor()
        .contextMenu {
            if source == .screen {
                Button("Pick Screen...") {
                    vm.pickScreen()
                }
                .disabled(vm.state != .idle)
            }
            Button("Remove \(title)", role: .destructive) {
                vm.removeSource(source)
            }
            .disabled(vm.state != .idle)
        }
    }

    private var header: some View {
        // Select and expand are separate gestures: tapping the row selects the source and
        // opens it (never collapses — that was the "click to select closes it" bug), while
        // the trailing chevron is the only thing that collapses it.
        HStack(spacing: 8) {
            Button {
                vm.selectSource(source)
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded = true
                }
            } label: {
                HStack(spacing: 11) {
                    BlitzIconTile(symbolName: source.symbolName, isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)

                            BlitzStatusDot(tone: status.tone.statusTone)
                        }

                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)

                    if let levels {
                        BlitzLevelMeter(levels: levels, active: status.tone == .active)
                            .frame(width: 30, height: 16)
                    }
                }
                .contentShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 22, height: 22)
                    .contentShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(isExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var expandedBody: some View {
        switch source {
        case .screen:
            ScreenSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.screen))
        case .camera:
            CameraSourceInspector(vm: vm, enabled: vm.isSourceConfigured(.camera))
        case .microphone:
            AudioSourceInspector(
                title: "Mic gain",
                source: .microphone,
                levels: vm.micLevels,
                gain: Binding(get: { vm.settings.microphoneGain }, set: { vm.setMicrophoneGain($0) }),
                vm: vm
            )
        case .systemAudio:
            AudioSourceInspector(
                title: "System gain",
                source: .systemAudio,
                levels: vm.sysLevels,
                gain: Binding(get: { vm.settings.systemAudioGain }, set: { vm.setSystemAudioGain($0) }),
                vm: vm
            )
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

private struct ScreenSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            captureSourceRow
            screenSettingsDivider
            captureAreaControl
        }
        .settingsPanelStyle()
    }

    private var captureSourceRow: some View {
        HStack(spacing: 10) {
            inspectorIcon(vm.settings.usesPickedScreenContent ? "rectangle.dashed" : "display", enabled: enabled)

            VStack(alignment: .leading, spacing: 2) {
                inspectorLabel("Source", enabled: enabled)
                Text(captureSourceLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.82 : 0.38))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            screenSettingIconButton(
                "rectangle.on.rectangle",
                help: "Choose a display, app, or window",
                disabled: vm.state != .idle
            ) {
                vm.pickScreen()
            }
        }
    }

    private var captureAreaControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                inspectorIcon("crop", enabled: enabled)

                inspectorLabel("Capture area", enabled: enabled)

                Spacer(minLength: 0)
            }

            // Full vs Window picks the screen INPUT region (left = devices). Manual
            // crop is NOT duplicated here: it lives once in the right inspector's
            // Screen-layer "Free crop" (rules #1/#3 — no floating Crop chrome, one home).
            HStack(spacing: 4) {
                captureAreaButton(
                    "Full",
                    icon: "display",
                    isSelected: vm.screenCaptureAreaSelection == .fullDisplay,
                    help: "Capture the full selected display or picked content",
                    disabled: !enabled
                ) {
                    vm.clearScreenCrop()
                }

                captureAreaButton(
                    "Window",
                    icon: "app.window",
                    isSelected: vm.screenCaptureAreaSelection == .activeWindow,
                    help: "Resize the active window to the current screen layout",
                    disabled: !enabled
                ) {
                    vm.fitFrontWindowForShorts()
                }
            }

            cropStatusRow

            if vm.screenCaptureAreaSelection == .activeWindow {
                windowScaleControl
            }
        }
    }

    private func windowPermissionHint(
        text: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BlitzUI.warning)
                .frame(width: 16, height: 16)

            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()
        }
        .padding(8)
        .background(BlitzUI.warning.opacity(0.10), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(BlitzUI.warning.opacity(0.30), lineWidth: 1)
        }
    }

    private var cropStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: captureAreaStatusIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.45 : 0.24))
                .frame(width: 16, height: 16)

            Text(captureAreaLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.58 : 0.3))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if vm.settings.screenCrop != nil || vm.isScreenCropModeEnabled {
                Button {
                    vm.clearScreenCrop()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                }
            .blitzGlassButton()
            .controlSize(.small)
            .disabled(!enabled)
            .pointingHandCursor()
            .help("Reset crop")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 8))
    }

    private var windowScaleControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !vm.hasAccessibilityAccessForWindowControls {
                windowPermissionHint(
                    text: "Allow Accessibility so BlitzRecorder can move and resize the window.",
                    actionTitle: "Allow"
                ) {
                    vm.requestAccessibilityForWindowControls()
                }
            }

            if !vm.isPersistentScreenCaptureAccessActive && !vm.settings.usesPickedScreenContent {
                windowPermissionHint(
                    text: "Allow Screen Recording to preview the captured window.",
                    actionTitle: "Settings"
                ) {
                    vm.openScreenRecordingSettings()
                }
            }

            HStack(spacing: 8) {
                inspectorIcon("app.window", enabled: enabled)

                VStack(alignment: .leading, spacing: 1) {
                    inspectorLabel("Active window", enabled: enabled)
                    Text(targetWindowLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(enabled ? 0.76 : 0.38))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                screenSettingIconButton(
                    "arrow.clockwise",
                    help: "Refresh active window",
                    disabled: false
                ) {
                    vm.refreshTargetWindow()
                }
            }

            Divider()
                .background(.white.opacity(0.07))

            HStack(spacing: 8) {
                Text("Window zoom")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(enabled ? 0.56 : 0.3))
                Spacer(minLength: 0)
                screenSettingIconButton(
                    "minus.magnifyingglass",
                    help: "Zoom out and refit the active window",
                    disabled: vm.targetWindowFitScale <= 0.75
                ) {
                    vm.zoomTargetWindowFit(by: -0.05)
                }

                Text(windowScaleLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(enabled ? 0.78 : 0.38))
                    .monospacedDigit()

                screenSettingIconButton(
                    "plus.magnifyingglass",
                    help: "Zoom in and refit the active window",
                    disabled: vm.targetWindowFitScale >= 1.25
                ) {
                    vm.zoomTargetWindowFit(by: 0.05)
                }

                screenSettingIconButton(
                    "arrow.counterclockwise",
                    help: "Reset window zoom to 100%",
                    disabled: false
                ) {
                    vm.fitFrontWindowForShorts(scale: 1.0)
                }
            }

            Slider(
                value: Binding(
                    get: { vm.targetWindowFitScale },
                    set: { value in
                        vm.setTargetWindowFitScale(CGFloat(value))
                    }
                ),
                in: 0.75...1.25,
                step: 0.05
            )
            .controlSize(.small)
            .disabled(!enabled)

            HStack {
                Text("75%")
                Spacer(minLength: 0)
                Text("100%")
                Spacer(minLength: 0)
                Text("125%")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(enabled ? 0.34 : 0.2))
            .monospacedDigit()

            Button {
                vm.fitFrontWindowForShorts()
            } label: {
                Label("Fit Window", systemImage: "rectangle.arrowtriangle.2.inward")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .disabled(!enabled)
            .pointingHandCursor()
            .help("Resize the active window to the current screen layout")
        }
        .padding(8)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 8))
    }

    private var screenSettingsDivider: some View {
        Divider()
            .background(.white.opacity(0.08))
    }

    private var captureSourceLabel: String {
        vm.settings.usesPickedScreenContent ? "Picked screen content" : "Display capture"
    }

    private var captureAreaLabel: String {
        if vm.isScreenCropModeEnabled {
            return "Editing capture crop"
        }
        guard vm.settings.screenCrop != nil else {
            return vm.settings.usesPickedScreenContent ? "Picked content" : "Full display"
        }
        return vm.screenCropLabel
    }

    private var captureAreaStatusIcon: String {
        switch vm.screenCaptureAreaSelection {
        case .fullDisplay:
            return vm.settings.usesPickedScreenContent ? "rectangle.dashed" : "display"
        case .activeWindow:
            return "app.window"
        case .manualCrop:
            return "crop"
        }
    }

    private var windowScaleLabel: String {
        "\(Int((vm.targetWindowFitScale * 100).rounded()))%"
    }

    private func captureAreaButton(
        _ title: String,
        icon: String,
        isSelected: Bool,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.62))
            .frame(maxWidth: .infinity, minHeight: 44)
            .multilineTextAlignment(.center)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .background(.white.opacity(isSelected ? 0.16 : 0.045), in: .rect(cornerRadius: 8))
        .pointingHandCursor()
        .help(help)
    }

    private func screenSettingIconButton(
        _ icon: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .disabled(!enabled || disabled)
        .pointingHandCursor()
        .help(help)
    }

    private var targetWindowLabel: String {
        guard let target = vm.targetWindowInfo else {
            return vm.targetWindowStatus.isEmpty ? "No active window detected" : vm.targetWindowStatus
        }
        if target.detail.isEmpty {
            return target.title
        }
        return "\(target.title) · \(target.detail)"
    }

}

private struct CameraSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The selector already shows the chosen camera by name + icon, so no separate
            // "Selected" row here — it would just repeat the dropdown label.
            WebcamSourceMenu(vm: vm, enabled: enabled)
            TransparentWebcamToggle(vm: vm, enabled: enabled)
        }
        .settingsPanelStyle()
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
                // Selector already names the chosen mic — no duplicate "Selected" row.
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
    /// The expanded device-card inspector body sits FLAT on the card surface — no
    /// nested fill/stroke. This used to wrap the content in another `blitzCard`,
    /// which stacked a card-inside-a-card; the device card and the divider above
    /// already contain it. Inset/rhythm now comes from `expandedBody`'s padding.
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
        vm.selectedSource = .screen
        vm.selectedLayer = .screen
        return vm
    }

    static func cameraSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.selectedScenePreset = .cameraInset
        settings.selectedCameraID = "preview-camera"
        let vm = makeViewModel(settings: settings)
        vm.selectedSource = .camera
        vm.selectedLayer = .camera
        return vm
    }

    static func micSelected() -> RecorderViewModel {
        var settings = previewSettings
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.camera]
        settings.selectedMicrophoneID = "preview-mic"
        let vm = makeViewModel(settings: settings)
        vm.selectedSource = .microphone
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
