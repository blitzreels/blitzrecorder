import BlitzRecorderCore
import SwiftUI

struct RemoteCameraControlsPane: View {
    @Bindable var vm: RecorderViewModel
    var showsStatusHeader = true
    @State private var selectedTab: RemoteCameraControlsTab = .camera

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsStatusHeader {
                statusHeader
            }

            if let capabilities = vm.selectedRemoteCameraCapabilities {
                tabPicker

                switch selectedTab {
                case .camera:
                    primaryCameraControls(capabilities: capabilities)
                case .advanced:
                    advancedCameraControls(capabilities: capabilities)
                }
            } else {
                waitingState
            }
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(RemoteCameraControlsTab.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.symbolName).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
    }

    @ViewBuilder
    private func primaryCameraControls(capabilities: RemoteCameraCapabilities) -> some View {
        remoteSection("Camera") {
            lensPicker(capabilities: capabilities)
            zoomSlider(capabilities: capabilities)
            torchToggle(capabilities: capabilities)
        }

        remoteSection("Quality") {
            qualityPicker(capabilities: capabilities)
        }
    }

    @ViewBuilder
    private func advancedCameraControls(capabilities: RemoteCameraCapabilities) -> some View {
        remoteSection("Format") {
            rotationPicker(capabilities: capabilities)
            HStack(alignment: .top, spacing: 8) {
                formatPicker(capabilities: capabilities)
                frameRatePicker(capabilities: capabilities)
            }
            stabilizationPicker(capabilities: capabilities)
        }

        remoteSection("Image") {
            remoteFocusControls(capabilities: capabilities)
            remoteExposureControls(capabilities: capabilities)
            remoteWhiteBalanceControls(capabilities: capabilities)
            resetImageControlsButton
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(remoteCameraStatus)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                vm.resetRemoteCameraSettings()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(!allowsFormatChanges || vm.selectedRemoteCameraCapabilities == nil)
            .pointingHandCursor()
            .help("Reset iPhone camera settings")
        }
    }

    private var waitingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting for camera controls")
                    .font(.system(size: 12, weight: .medium))
                Text("Keep the iPhone app open and paired.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func remoteSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lensPicker(capabilities: RemoteCameraCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            controlLabel("Lens")
            Picker(
                "",
                selection: Binding(
                    get: { vm.selectedRemoteCameraTelemetry?.activeSettings.lens ?? capabilities.supportedLenses.first ?? .wide },
                    set: { vm.setRemoteCameraLens($0) }
                )
            ) {
                ForEach(capabilities.supportedLenses, id: \.self) { lens in
                    Text(lens.displayName).tag(lens)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .disabled(!allowsLiveCameraChanges)
    }

    private func rotationPicker(capabilities: RemoteCameraCapabilities) -> some View {
        modePicker(
            title: "Phone mount",
            selection: Binding(
                get: { currentRemoteSettings.rotationDegrees },
                set: { vm.setRemoteCameraRotationDegrees($0) }
            )
        ) {
            ForEach(capabilities.supportedRotationDegrees, id: \.self) { degrees in
                Text(rotationMountLabel(for: degrees)).tag(degrees)
            }
        }
        .disabled(!allowsFormatChanges || capabilities.supportedRotationDegrees.count <= 1)
    }

    private func qualityPicker(capabilities: RemoteCameraCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            modePicker(
                title: "Quality",
                selection: Binding(
                    get: { currentRemoteSettings.captureProfileID },
                    set: { vm.setRemoteCameraCaptureProfile($0) }
                )
            ) {
                ForEach(capabilities.supportedCaptureProfiles, id: \.id) { profile in
                    Text(profile.displayName)
                        .tag(profile.id)
                        .disabled(!profile.isAvailable)
                }
            }
            if let reason = profileUnavailableReason(.proRes422, capabilities: capabilities) {
                Label(reason, systemImage: "info.circle")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!allowsFormatChanges || availableRemoteFormats(capabilities).isEmpty)
    }

    private func formatPicker(capabilities: RemoteCameraCapabilities) -> some View {
        labeledPicker(
            "Resolution",
            selection: Binding(
                get: { currentFormatID(capabilities) },
                set: { id in
                    let frameRates = frameRates(for: id, capabilities: capabilities)
                    let currentFrameRate = currentRemoteSettings.frameRate
                    vm.setRemoteCameraFormat(
                        id: id,
                        frameRate: frameRates.contains(currentFrameRate) ? currentFrameRate : (frameRates.first ?? currentFrameRate)
                    )
                }
            )
        ) {
            ForEach(availableRemoteFormats(capabilities), id: \.id) { format in
                Text("\(format.width)x\(format.height)").tag(format.id)
            }
        }
        .disabled(!allowsFormatChanges)
    }

    private func frameRatePicker(capabilities: RemoteCameraCapabilities) -> some View {
        labeledPicker(
            "FPS",
            selection: Binding(
                get: { currentRemoteSettings.frameRate },
                set: { vm.setRemoteCameraFormat(id: currentFormatID(capabilities), frameRate: $0) }
            )
        ) {
            ForEach(frameRates(for: currentFormatID(capabilities), capabilities: capabilities), id: \.self) { frameRate in
                Text("\(frameRate)").tag(frameRate)
            }
        }
        .disabled(!allowsFormatChanges || frameRates(for: currentFormatID(capabilities), capabilities: capabilities).isEmpty)
    }

    private func zoomSlider(capabilities: RemoteCameraCapabilities) -> some View {
        let minimumZoom = capabilities.minimumZoomFactor
        let maximumZoom = max(minimumZoom, capabilities.maximumZoomFactor)
        let range = minimumZoom...maximumZoom
        let value = min(maximumZoom, max(minimumZoom, remoteZoom))
        return remoteSlider(
            title: "Zoom",
            value: value,
            range: range,
            step: 0.1,
            label: String(format: "%.1fx", value),
            isEnabled: maximumZoom > minimumZoom,
            onChange: vm.setRemoteCameraZoom
        )
    }

    @ViewBuilder
    private func remoteFocusControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsManualFocus || capabilities.supportsFocusLock {
            modePicker(
                title: "Focus",
                selection: Binding(
                    get: { currentRemoteSettings.focusMode },
                    set: { vm.setRemoteCameraFocusMode($0) }
                )
            ) {
                ForEach(RemoteCameraFocusMode.allCases.filter { mode in
                    switch mode {
                    case .continuousAuto: true
                    case .locked: capabilities.supportsFocusLock
                    case .manual: capabilities.supportsManualFocus
                    }
                }, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!allowsLiveCameraChanges)

            if currentRemoteSettings.focusMode == .manual {
                remoteSlider(
                    title: "Focus position",
                    value: currentRemoteSettings.focusPosition,
                    range: 0...1,
                    step: 0.01,
                    label: String(format: "%.2f", currentRemoteSettings.focusPosition),
                    isEnabled: capabilities.supportsManualFocus,
                    onChange: vm.setRemoteCameraFocusPosition
                )
            }
        }
    }

    @ViewBuilder
    private func remoteExposureControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsManualExposure || capabilities.supportsExposureLock {
            modePicker(
                title: "Exposure",
                selection: Binding(
                    get: { currentRemoteSettings.exposureMode },
                    set: { vm.setRemoteCameraExposureMode($0) }
                )
            ) {
                ForEach(RemoteCameraExposureMode.allCases.filter { mode in
                    switch mode {
                    case .continuousAuto: true
                    case .locked: capabilities.supportsExposureLock
                    case .manual: capabilities.supportsManualExposure
                    }
                }, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!allowsLiveCameraChanges)
        }

        remoteSlider(
            title: "Brightness",
            value: currentRemoteSettings.exposureBias,
            range: capabilities.minimumExposureBias...capabilities.maximumExposureBias,
            step: 0.1,
            label: String(format: "%+.1f", currentRemoteSettings.exposureBias),
            isEnabled: capabilities.maximumExposureBias > capabilities.minimumExposureBias,
            onChange: vm.setRemoteCameraExposureBias
        )

        HStack {
            Spacer(minLength: 0)
            Button {
                vm.resetRemoteCameraExposureBias()
            } label: {
                Label("Reset brightness", systemImage: "sun.max")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(vm.selectedRemoteCameraCapabilities == nil)
            .pointingHandCursor()
            .help("Set exposure to Auto and brightness to 0")
        }

        if currentRemoteSettings.exposureMode == .manual,
           let minimumISO = capabilities.minimumISO,
           let maximumISO = capabilities.maximumISO {
            remoteSlider(
                title: "ISO",
                value: currentRemoteSettings.iso ?? minimumISO,
                range: minimumISO...maximumISO,
                step: 10,
                label: "\(Int(currentRemoteSettings.iso ?? minimumISO))",
                isEnabled: capabilities.supportsManualExposure && maximumISO > minimumISO,
                onChange: { vm.setRemoteCameraISO($0) }
            )
        }

        if currentRemoteSettings.exposureMode == .manual,
           let minimumShutter = capabilities.minimumShutterDurationSeconds,
           let maximumShutter = capabilities.maximumShutterDurationSeconds {
            remoteSlider(
                title: "Shutter",
                value: currentRemoteSettings.shutterDurationSeconds ?? max(minimumShutter, 1.0 / 60.0),
                range: minimumShutter...min(maximumShutter, 1.0),
                step: 0.001,
                label: shutterLabel(currentRemoteSettings.shutterDurationSeconds ?? max(minimumShutter, 1.0 / 60.0)),
                isEnabled: capabilities.supportsManualExposure && maximumShutter > minimumShutter,
                onChange: { vm.setRemoteCameraShutterDuration($0) }
            )
        }
    }

    @ViewBuilder
    private func remoteWhiteBalanceControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsWhiteBalanceLock || capabilities.supportsManualWhiteBalance {
            modePicker(
                title: "Color",
                selection: Binding(
                    get: { currentRemoteSettings.whiteBalanceMode },
                    set: { vm.setRemoteCameraWhiteBalanceMode($0) }
                )
            ) {
                ForEach(RemoteCameraWhiteBalanceMode.allCases.filter { mode in
                    switch mode {
                    case .continuousAuto: true
                    case .locked: capabilities.supportsWhiteBalanceLock
                    case .manual: capabilities.supportsManualWhiteBalance
                    }
                }, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!allowsLiveCameraChanges)

            if currentRemoteSettings.whiteBalanceMode == .manual {
                remoteSlider(
                    title: "Temperature",
                    value: currentRemoteSettings.whiteBalanceTemperature,
                    range: 2_500...9_500,
                    step: 100,
                    label: "\(Int(currentRemoteSettings.whiteBalanceTemperature))K",
                    isEnabled: capabilities.supportsManualWhiteBalance,
                    onChange: { vm.setRemoteCameraWhiteBalance(temperature: $0, tint: currentRemoteSettings.whiteBalanceTint) }
                )
                remoteSlider(
                    title: "Tint",
                    value: currentRemoteSettings.whiteBalanceTint,
                    range: -150...150,
                    step: 1,
                    label: "\(Int(currentRemoteSettings.whiteBalanceTint))",
                    isEnabled: capabilities.supportsManualWhiteBalance,
                    onChange: { vm.setRemoteCameraWhiteBalance(temperature: currentRemoteSettings.whiteBalanceTemperature, tint: $0) }
                )
            }
        }
    }

    @ViewBuilder
    private func stabilizationPicker(capabilities: RemoteCameraCapabilities) -> some View {
        if !capabilities.supportedStabilizationModes.isEmpty {
            modePicker(
                title: "Stabilization",
                selection: Binding(
                    get: { currentRemoteSettings.stabilizationMode },
                    set: { vm.setRemoteCameraStabilizationMode($0) }
                )
            ) {
                ForEach(capabilities.supportedStabilizationModes, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(!allowsFormatChanges || capabilities.supportedStabilizationModes.count <= 1)
        }
    }

    private func torchToggle(capabilities: RemoteCameraCapabilities) -> some View {
        HStack(spacing: 10) {
            Label("Torch", systemImage: "flashlight.on.fill")
                .font(.system(size: 12, weight: .regular))
            Spacer(minLength: 0)
            if !capabilities.supportsTorch {
                Text("Unavailable")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Toggle("", isOn: Binding(
                get: { capabilities.supportsTorch && (vm.selectedRemoteCameraTelemetry?.activeSettings.torchEnabled ?? false) },
                set: { vm.setRemoteCameraTorchEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .disabled(!allowsLiveCameraChanges || !capabilities.supportsTorch)
    }

    private func modePicker<Value: Hashable, Content: View>(
        title: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            controlLabel(title)
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
        }
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
    }

    private func remoteSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        label: String,
        isEnabled: Bool = true,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let sliderRange = range.lowerBound < range.upperBound ? range : range.lowerBound...(range.lowerBound + max(step, 1))
        let sliderValue = min(sliderRange.upperBound, max(sliderRange.lowerBound, value))
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                controlLabel(title)
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: onChange
                ),
                in: sliderRange,
                step: step
            )
            .controlSize(.small)
            .disabled(!allowsLiveCameraChanges || !isEnabled)
        }
    }

    private var resetImageControlsButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                vm.resetRemoteCameraImageSettings()
            } label: {
                Label("Auto image", systemImage: "sun.max")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(vm.selectedRemoteCameraCapabilities == nil)
            .pointingHandCursor()
            .help("Reset focus, brightness, and color to auto")
        }
    }

    private var deviceName: String {
        vm.selectedRemoteCameraCapabilities?.deviceName ?? "iPhone Camera"
    }

    private var remoteCameraStatus: String {
        guard let telemetry = vm.selectedRemoteCameraTelemetry else {
            return "Waiting for iPhone"
        }
        if telemetry.phase == .transferring,
           let progress = telemetry.transferProgress {
            return "Transferring \(Int((progress.fraction * 100).rounded()))%"
        }
        if let previewHealth = telemetry.previewHealth,
           previewHealth.framesSent > 0,
           !previewHealth.isHealthy {
            if let lastFrameAgeSeconds = previewHealth.lastFrameAgeSeconds,
               lastFrameAgeSeconds >= 2 {
                return "Preview feed stale"
            }
            return "Preview degraded - \(Int((previewHealth.droppedFrameRatio * 100).rounded()))% drop"
        }
        return "\(telemetry.phase.rawValue.capitalized) - \(Int(telemetry.elapsedSeconds))s"
    }

    private var allowsLiveCameraChanges: Bool {
        vm.state == .idle || vm.state == .recording
    }

    private var allowsFormatChanges: Bool {
        vm.state == .idle
    }

    private var remoteZoom: Double {
        vm.selectedRemoteCameraTelemetry?.activeSettings.zoomFactor ?? 1
    }

    private var currentRemoteSettings: RemoteCameraSettings {
        vm.selectedRemoteCameraTelemetry?.activeSettings ?? RemoteCameraSettings()
    }

    private func currentFormatID(_ capabilities: RemoteCameraCapabilities) -> String {
        currentRemoteSettings.formatID ?? availableRemoteFormats(capabilities).first?.id ?? ""
    }

    private func frameRates(for formatID: String, capabilities: RemoteCameraCapabilities) -> [Int] {
        let formats = availableRemoteFormats(capabilities)
        return formats.first(where: { $0.id == formatID })?.frameRates
            ?? formats.first?.frameRates
            ?? [30]
    }

    private func availableRemoteFormats(_ capabilities: RemoteCameraCapabilities) -> [RemoteCameraFormat] {
        guard let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == currentRemoteSettings.captureProfileID }),
              !profile.supportedFormatIDs.isEmpty else {
            return capabilities.supportedFormats
        }
        let supportedIDs = Set(profile.supportedFormatIDs)
        let formats = capabilities.supportedFormats.filter { supportedIDs.contains($0.id) }
        return formats.isEmpty ? capabilities.supportedFormats : formats
    }

    private func profileUnavailableReason(
        _ profileID: RemoteCameraCaptureProfileID,
        capabilities: RemoteCameraCapabilities
    ) -> String? {
        guard let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == profileID }),
              !profile.isAvailable else {
            return nil
        }
        return profile.unavailableReason
    }

    private func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0s" }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded()))"
        }
        return String(format: "%.2fs", seconds)
    }

    private func rotationMountLabel(for degrees: Int) -> String {
        switch RemoteCameraSettings.normalizedRotationDegrees(degrees) {
        case 0:
            return "Portrait"
        case 90:
            return "Lens right"
        case 180:
            return "Lens top"
        case 270:
            return "Lens left"
        default:
            return "\(degrees)deg"
        }
    }
}

private enum RemoteCameraControlsTab: String, CaseIterable {
    case camera
    case advanced

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .advanced: return "Advanced"
        }
    }

    var symbolName: String {
        switch self {
        case .camera: return "camera.aperture"
        case .advanced: return "slider.horizontal.3"
        }
    }
}
