import BlitzRecorderCore
import SwiftUI

struct RemoteCameraControlsPane: View {
    @Bindable var vm: RecorderViewModel
    var showsStatusHeader = true
    @State private var selectedTab: RemoteCameraControlsTab = .camera
    @State private var pendingCinematicAperture: Double?

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
        }

        remoteSection("Quality") {
            qualityPicker(capabilities: capabilities)
            colorModePicker(capabilities: capabilities)
            cinematicControls(capabilities: capabilities)
        }
    }

    @ViewBuilder
    private func advancedCameraControls(capabilities: RemoteCameraCapabilities) -> some View {
        remoteSection("Format") {
            HStack(alignment: .top, spacing: 8) {
                formatPicker(capabilities: capabilities)
                frameRatePicker(capabilities: capabilities)
            }
            helperText("Higher resolution is sharper. 30 fps is the best default for iPhone video.")
            stabilizationPicker(capabilities: capabilities)
        }

        remoteSection("Fine tune") {
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
                Label("Auto", systemImage: "wand.and.sparkles")
                    .font(.system(size: 11, weight: .medium))
            }
            .blitzGlassButton()
            .controlSize(.small)
            .disabled(!allowsFormatChanges || vm.selectedRemoteCameraCapabilities == nil)
            .pointingHandCursor()
            .help("Set iPhone camera controls to Auto")
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
            if cinematicLocksFormatControls {
                helperText("Turn Cinematic off to change lens.")
            }
        }
        .disabled(!allowsLiveCameraChanges || cinematicLocksFormatControls)
    }

    private func qualityPicker(capabilities: RemoteCameraCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            modePicker(
                title: "Recording",
                selection: Binding(
                    get: { currentRemoteSettings.captureProfileID },
                    set: { vm.setRemoteCameraCaptureProfile($0) }
                )
            ) {
                ForEach(capabilities.supportedCaptureProfiles, id: \.id) { profile in
                    Text(captureProfileLabel(profile.id))
                        .tag(profile.id)
                        .disabled(!profile.isAvailable)
                }
            }
            Text(captureProfileHelpText(currentRemoteSettings.captureProfileID))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = profileUnavailableReason(.proRes422, capabilities: capabilities) {
                Label(reason, systemImage: "info.circle")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if cinematicLocksFormatControls {
                helperText("Turn Cinematic off to change recording format.")
            }
        }
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls || availableRemoteFormats(capabilities).isEmpty)
    }

    private func colorModePicker(capabilities: RemoteCameraCapabilities) -> some View {
        let modes = availableColorModes(capabilities)
        return VStack(alignment: .leading, spacing: 5) {
            if modes.count > 1 || currentRemoteSettings.colorMode != .standard {
                modePicker(
                    title: "Color",
                    selection: Binding(
                        get: { currentRemoteSettings.colorMode },
                        set: { vm.setRemoteCameraColorMode($0) }
                    )
                ) {
                    ForEach(modes, id: \.self) { mode in
                        Text(colorModeLabel(mode)).tag(mode)
                    }
                }
                Text(colorModeHelpText(currentRemoteSettings.colorMode))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls)
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
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls)
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
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls || frameRates(for: currentFormatID(capabilities), capabilities: capabilities).isEmpty)
    }

    private func cinematicControls(capabilities: RemoteCameraCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if capabilities.supportsCinematicVideo {
                HStack(spacing: 10) {
                    Label("Cinematic depth", systemImage: "camera.aperture")
                        .font(.system(size: 12, weight: .regular))
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { currentRemoteSettings.cinematicVideoEnabled },
                        set: { vm.setRemoteCameraCinematicVideoEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .disabled(!allowsFormatChanges)

                Text("iPhone Cinematic mode with adjustable depth of field.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if currentRemoteSettings.cinematicVideoEnabled {
                    helperText("Lens, recording format, resolution, FPS, smoothing, and sharpness are locked while Cinematic is on.")
                }
            } else {
                Label("Cinematic unavailable", systemImage: "camera.aperture")
                    .font(.system(size: 12, weight: .regular))
                helperText(cinematicUnavailableReason())
            }

            if capabilities.supportsCinematicVideo,
               let minimumAperture = capabilities.minimumCinematicAperture,
               let maximumAperture = capabilities.maximumCinematicAperture,
               minimumAperture < maximumAperture {
                let aperture = min(
                    maximumAperture,
                    max(
                        minimumAperture,
                        currentRemoteSettings.cinematicAperture
                            ?? capabilities.defaultCinematicAperture
                            ?? minimumAperture
                    )
                )
                cinematicApertureSlider(
                    value: aperture,
                    range: minimumAperture...maximumAperture,
                    step: 0.1,
                    isEnabled: allowsFormatChanges && currentRemoteSettings.cinematicVideoEnabled
                )
            }
        }
        .help("Cinematic settings apply before recording starts")
    }

    @ViewBuilder
    private func remoteFocusControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsManualFocus || capabilities.supportsFocusLock {
            modePicker(
                title: "Sharpness",
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
            .disabled(!allowsLiveCameraChanges || currentRemoteSettings.cinematicVideoEnabled)
            helperText(currentRemoteSettings.cinematicVideoEnabled
                ? "Cinematic controls focus automatically."
                : focusModeHelpText(currentRemoteSettings.focusMode))

            if currentRemoteSettings.focusMode == .manual {
                remoteSlider(
                    title: "Focus position",
                    value: currentRemoteSettings.focusPosition,
                    range: 0...1,
                    step: 0.01,
                    label: String(format: "%.2f", currentRemoteSettings.focusPosition),
                    isEnabled: capabilities.supportsManualFocus && !currentRemoteSettings.cinematicVideoEnabled,
                    onChange: vm.setRemoteCameraFocusPosition
                )
            }
        }
    }

    @ViewBuilder
    private func remoteExposureControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsManualExposure || capabilities.supportsExposureLock {
            modePicker(
                title: "Light",
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
            helperText(exposureModeHelpText(currentRemoteSettings.exposureMode))
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
            .blitzGlassButton()
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
            helperText(whiteBalanceModeHelpText(currentRemoteSettings.whiteBalanceMode))

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
                title: "Smoother video",
                selection: Binding(
                    get: { currentRemoteSettings.stabilizationMode },
                    set: { vm.setRemoteCameraStabilizationMode($0) }
                )
            ) {
                ForEach(capabilities.supportedStabilizationModes, id: \.self) { mode in
                    Text(stabilizationModeLabel(mode)).tag(mode)
                }
            }
            .disabled(!allowsFormatChanges || cinematicLocksFormatControls || capabilities.supportedStabilizationModes.count <= 1)
            helperText(stabilizationModeHelpText(currentRemoteSettings.stabilizationMode))
        }
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

    private func helperText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
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

    private func cinematicApertureSlider(
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        isEnabled: Bool
    ) -> some View {
        let sliderRange = range.lowerBound < range.upperBound ? range : range.lowerBound...(range.lowerBound + max(step, 1))
        let sliderValue = min(sliderRange.upperBound, max(sliderRange.lowerBound, pendingCinematicAperture ?? value))
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                controlLabel("Depth of field")
                Spacer(minLength: 0)
                Text(String(format: "f/%.1f", sliderValue))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { pendingCinematicAperture = $0 }
                ),
                in: sliderRange,
                step: step,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    let committedValue = min(
                        sliderRange.upperBound,
                        max(sliderRange.lowerBound, pendingCinematicAperture ?? sliderValue)
                    )
                    pendingCinematicAperture = nil
                    vm.setRemoteCameraCinematicAperture(committedValue)
                }
            )
            .controlSize(.small)
            .disabled(!allowsFormatChanges || !isEnabled)
            helperText("Lower f-number means stronger blur. Applies when you release the slider.")
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
            .blitzGlassButton()
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
                return "Waiting for live view"
            }
            return "iPhone connected"
        }
        if let captureWarning = telemetry.captureWarning,
           !captureWarning.isEmpty {
            return captureWarning
        }
        return "\(telemetry.phase.rawValue.capitalized) - \(Int(telemetry.elapsedSeconds))s"
    }

    private var allowsLiveCameraChanges: Bool {
        vm.state == .idle || vm.state == .recording
    }

    private var allowsFormatChanges: Bool {
        vm.state == .idle
    }

    private var cinematicLocksFormatControls: Bool {
        currentRemoteSettings.cinematicVideoEnabled
    }

    private var currentRemoteSettings: RemoteCameraSettings {
        vm.selectedRemoteCameraTelemetry?.activeSettings ?? RemoteCameraSettings()
    }

    private func currentFormatID(_ capabilities: RemoteCameraCapabilities) -> String {
        currentRemoteSettings.formatID ?? availableRemoteFormats(capabilities).first?.id ?? ""
    }

    private func frameRates(for formatID: String, capabilities: RemoteCameraCapabilities) -> [Int] {
        let formats = availableRemoteFormats(capabilities)
        let format = formats.first(where: { $0.id == formatID }) ?? formats.first
        guard let format else { return [30] }
        return RemoteCameraSettingsResolver.compatibleFrameRates(
            for: format,
            profileID: currentRemoteSettings.captureProfileID,
            colorMode: currentRemoteSettings.colorMode,
            profiles: capabilities.supportedCaptureProfiles
        )
    }

    private func availableColorModes(_ capabilities: RemoteCameraCapabilities) -> [RemoteCameraColorMode] {
        var formats = availableRemoteFormats(capabilities)
        if currentRemoteSettings.captureProfileID != .proRes422,
           let proResProfile = capabilities.supportedCaptureProfiles.first(where: { $0.id == .proRes422 && $0.isAvailable }),
           !proResProfile.supportedFormatIDs.isEmpty {
            let supportedIDs = Set(proResProfile.supportedFormatIDs)
            formats = capabilities.supportedFormats.filter { supportedIDs.contains($0.id) }
        }
        let modes = Set(formats.flatMap(\.colorModes))
        let ordered = RemoteCameraColorMode.allCases.filter { mode in
            mode == .standard || modes.contains(mode)
        }
        return ordered.isEmpty ? [.standard] : ordered
    }

    private func colorModeLabel(_ mode: RemoteCameraColorMode) -> String {
        switch mode {
        case .standard:
            return "Standard"
        case .appleLog:
            return "Log"
        case .appleLog2:
            return "Log 2"
        }
    }

    private func colorModeHelpText(_ mode: RemoteCameraColorMode) -> String {
        switch mode {
        case .standard:
            return "The normal iPhone video color pipeline."
        case .appleLog:
            return "Flat Apple Log ProRes for grading. Preview LUT is not applied yet."
        case .appleLog2:
            return "Apple Log 2 ProRes for newer iPhones. Preview LUT is not applied yet."
        }
    }

    private func availableRemoteFormats(_ capabilities: RemoteCameraCapabilities) -> [RemoteCameraFormat] {
        guard let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == currentRemoteSettings.captureProfileID }),
              !profile.supportedFormatIDs.isEmpty else {
            return capabilities.supportedFormats
        }
        let supportedIDs = Set(profile.supportedFormatIDs)
        var formats = capabilities.supportedFormats.filter { supportedIDs.contains($0.id) }
        if currentRemoteSettings.colorMode != .standard {
            let colorModeFormats = formats.filter { $0.colorModes.contains(currentRemoteSettings.colorMode) }
            if !colorModeFormats.isEmpty {
                formats = colorModeFormats
            }
        }
        return formats
    }

    private func profileUnavailableReason(
        _ profileID: RemoteCameraCaptureProfileID,
        capabilities: RemoteCameraCapabilities
    ) -> String? {
        guard let profile = capabilities.supportedCaptureProfiles.first(where: { $0.id == profileID }),
              !profile.isAvailable else {
            return nil
        }
        switch profileID {
        case .automatic:
            return profile.unavailableReason ?? "Best is unavailable for this iPhone camera setting."
        case .highEfficiency:
            return profile.unavailableReason ?? "Small files are unavailable for this iPhone camera setting."
        case .proRes422:
            return profile.unavailableReason ?? "Pro means ProRes, and ProRes is unavailable for this iPhone camera setting."
        }
    }

    private func cinematicUnavailableReason() -> String {
        var checks: [String] = []
        if currentRemoteSettings.captureProfileID == .proRes422 {
            checks.append("switch Recording to Best")
        }
        if currentRemoteSettings.lens != .wide {
            checks.append("switch Lens to Wide")
        }
        if currentRemoteSettings.frameRate != 30 {
            checks.append("switch FPS to 30")
        }
        if checks.isEmpty {
            return "Phone did not report Cinematic support. Reopen the latest iPhone app build and pair again."
        }
        return "Phone did not report Cinematic support. Try: \(checks.joined(separator: ", "))."
    }

    private func captureProfileLabel(_ profileID: RemoteCameraCaptureProfileID) -> String {
        switch profileID {
        case .automatic:
            return "Best"
        case .highEfficiency:
            return "Small"
        case .proRes422:
            return "ProRes"
        }
    }

    private func captureProfileHelpText(_ profileID: RemoteCameraCaptureProfileID) -> String {
        switch profileID {
        case .automatic:
            return "Recommended. The iPhone chooses the best recording format."
        case .highEfficiency:
            return "Smaller files. Good for long recordings."
        case .proRes422:
            return "Very large ProRes files for editing. Not Cinematic mode."
        }
    }

    private func focusModeHelpText(_ mode: RemoteCameraFocusMode) -> String {
        switch mode {
        case .continuousAuto:
            return "Auto keeps the subject sharp as it moves."
        case .locked:
            return "Locked keeps the current focus and stops hunting."
        case .manual:
            return "Manual lets you set the focus distance yourself."
        }
    }

    private func exposureModeHelpText(_ mode: RemoteCameraExposureMode) -> String {
        switch mode {
        case .continuousAuto:
            return "Auto lets the iPhone adjust to brighter or darker scenes."
        case .locked:
            return "Locked keeps the current light level from changing."
        case .manual:
            return "Manual gives you ISO and shutter controls."
        }
    }

    private func whiteBalanceModeHelpText(_ mode: RemoteCameraWhiteBalanceMode) -> String {
        switch mode {
        case .continuousAuto:
            return "Auto keeps colors natural as the room light changes."
        case .locked:
            return "Locked stops colors from shifting during a take."
        case .manual:
            return "Manual lets you set warmth and tint yourself."
        }
    }

    private func stabilizationModeHelpText(_ mode: RemoteCameraStabilizationMode) -> String {
        switch mode {
        case .off:
            return "Off records without extra smoothing."
        case .standard:
            return "Standard smooths small hand movements."
        case .cinematic:
            return "Strong smoothing reduces bigger hand movements and may crop the image."
        case .auto:
            return "Auto lets the iPhone choose the best smoothing."
        }
    }

    private func stabilizationModeLabel(_ mode: RemoteCameraStabilizationMode) -> String {
        switch mode {
        case .off:
            return "Off"
        case .standard:
            return "Normal"
        case .cinematic:
            return "Strong"
        case .auto:
            return "Auto"
        }
    }

    private func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0s" }
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded()))"
        }
        return String(format: "%.2fs", seconds)
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
