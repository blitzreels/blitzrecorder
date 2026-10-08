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
        BlitzSegmentedPicker(configuration: .init(
            title: "Camera controls",
            options: RemoteCameraControlsTab.allCases,
            selection: $selectedTab,
            label: { $0.title },
            symbolName: { $0.symbolName }
        ))
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
                .font(BlitzType.glyph(14))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(BlitzType.label)
                    .lineLimit(1)
                Text(remoteCameraStatus)
                    .font(BlitzType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                vm.resetRemoteCameraSettings()
            } label: {
                Label("Auto", systemImage: "wand.and.sparkles")
                    .font(BlitzType.captionEmphasis)
            }
            .blitzButton(.secondary)
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
                    .font(BlitzType.label)
                Text("Keep the iPhone app open and paired.")
                    .font(BlitzType.caption)
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
            Text(title)
                .font(BlitzType.captionEmphasis)
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
            BlitzSegmentedPicker(configuration: .init(
                title: "Lens",
                options: capabilities.supportedLenses,
                selection: Binding(
                    get: { vm.selectedRemoteCameraTelemetry?.activeSettings.lens ?? capabilities.supportedLenses.first ?? .wide },
                    set: { vm.setRemoteCameraLens($0) }
                ),
                label: { $0.displayName }
            ))
            .controlSize(.small)
            if cinematicLocksFormatControls {
                helperText("Turn Cinematic off to change lens.")
            }
        }
        .disabled(!allowsLiveCameraChanges || cinematicLocksFormatControls)
    }

    private func qualityPicker(capabilities: RemoteCameraCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            modePicker(.init(
                title: "Recording",
                options: capabilities.supportedCaptureProfiles.map(\.id),
                selection: Binding(
                    get: { currentRemoteSettings.captureProfileID },
                    set: { vm.setRemoteCameraCaptureProfile($0) }
                ),
                label: RemoteCameraControlsCopy.captureProfileLabel,
                isOptionEnabled: { id in
                    capabilities.supportedCaptureProfiles.first { $0.id == id }?.isAvailable == true
                }
            ))
            Text(RemoteCameraControlsCopy.captureProfileHelpText(currentRemoteSettings.captureProfileID))
                .font(BlitzType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = profileUnavailableReason(.proRes422, capabilities: capabilities) {
                Label(reason, systemImage: "info.circle")
                    .font(BlitzType.caption)
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
                modePicker(.init(
                    title: "Color",
                    options: modes,
                    selection: Binding(
                        get: { currentRemoteSettings.colorMode },
                        set: { vm.setRemoteCameraColorMode($0) }
                    ),
                    label: RemoteCameraControlsCopy.colorModeLabel
                ))
                helperText(RemoteCameraControlsCopy.colorModeHelpText(currentRemoteSettings.colorMode))
            }
        }
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls)
    }

    private func formatPicker(capabilities: RemoteCameraCapabilities) -> some View {
        labeledDropdown(.init(
            title: "Resolution",
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
            ),
            options: availableRemoteFormats(capabilities).map { format in
                .init(value: format.id, title: "\(format.width) × \(format.height)", detail: nil)
            }
        ))
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls)
    }

    private func frameRatePicker(capabilities: RemoteCameraCapabilities) -> some View {
        labeledDropdown(.init(
            title: "Frame rate",
            selection: Binding(
                get: { currentRemoteSettings.frameRate },
                set: { vm.setRemoteCameraFormat(id: currentFormatID(capabilities), frameRate: $0) }
            ),
            options: frameRates(for: currentFormatID(capabilities), capabilities: capabilities).map { frameRate in
                .init(value: frameRate, title: "\(frameRate) FPS", detail: nil)
            }
        ))
        .disabled(!allowsFormatChanges || cinematicLocksFormatControls || frameRates(for: currentFormatID(capabilities), capabilities: capabilities).isEmpty)
    }

    private func cinematicControls(capabilities: RemoteCameraCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if capabilities.supportsCinematicVideo {
                Toggle("Cinematic depth", isOn: Binding(
                    get: { currentRemoteSettings.cinematicVideoEnabled },
                    set: { vm.setRemoteCameraCinematicVideoEnabled($0) }
                ))
                .toggleStyle(.blitzSwitch)
                .disabled(!allowsFormatChanges)

                Text("iPhone Cinematic mode with adjustable depth of field.")
                    .font(BlitzType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if currentRemoteSettings.cinematicVideoEnabled {
                    helperText("Lens, recording format, resolution, FPS, smoothing, and sharpness are locked while Cinematic is on.")
                }
            } else {
                Label("Cinematic unavailable", systemImage: "camera.aperture")
                    .font(BlitzType.body)
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

    func modePicker<Value: Hashable>(
        _ configuration: BlitzSegmentedPicker<Value>.Configuration
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            controlLabel(configuration.title)
            BlitzSegmentedPicker(configuration: configuration)
                .controlSize(.small)
        }
    }

    func controlLabel(_ title: String) -> some View {
        Text(title)
            .font(BlitzType.caption)
            .foregroundStyle(.secondary)
    }

    func helperText(_ text: String) -> some View {
        Text(text)
            .font(BlitzType.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    struct SliderRangeRequest {
        let range: ClosedRange<Double>
        let step: Double
    }

    func sliderRange(_ request: SliderRangeRequest) -> ClosedRange<Double> {
        let range = request.range
        return range.lowerBound < range.upperBound ? range : range.lowerBound...(range.lowerBound + max(request.step, 1))
    }

    struct SliderHeader {
        let title: String
        let value: String
    }

    func sliderHeader(_ header: SliderHeader) -> some View {
        HStack {
            controlLabel(header.title)
            Spacer(minLength: 0)
            Text(header.value)
                .font(BlitzType.caption.monospaced())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func cinematicApertureSlider(
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        isEnabled: Bool
    ) -> some View {
        let sliderRange = self.sliderRange(.init(range: range, step: step))
        let sliderValue = min(sliderRange.upperBound, max(sliderRange.lowerBound, pendingCinematicAperture ?? value))
        return VStack(alignment: .leading, spacing: 5) {
            sliderHeader(.init(title: "Depth of field", value: String(format: "f/%.1f", sliderValue)))
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
