import BlitzRecorderCore
import SwiftUI

extension RemoteCameraControlsPane {
    @ViewBuilder
    func remoteFocusControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsManualFocus || capabilities.supportsFocusLock {
            modePicker(.init(
                title: "Sharpness",
                options: RemoteCameraFocusMode.allCases.filter { mode in
                    switch mode {
                    case .continuousAuto: true
                    case .locked: capabilities.supportsFocusLock
                    case .manual: capabilities.supportsManualFocus
                    }
                },
                selection: Binding(
                    get: { currentRemoteSettings.focusMode },
                    set: { vm.setRemoteCameraFocusMode($0) }
                ),
                label: { $0.displayName }
            ))
            .disabled(!allowsLiveCameraChanges || currentRemoteSettings.cinematicVideoEnabled)
            helperText(currentRemoteSettings.cinematicVideoEnabled
                ? "Cinematic controls focus automatically."
                : RemoteCameraControlsCopy.focusModeHelpText(currentRemoteSettings.focusMode))

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
    func remoteExposureControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsManualExposure || capabilities.supportsExposureLock {
            modePicker(.init(
                title: "Light",
                options: RemoteCameraExposureMode.allCases.filter { mode in
                    switch mode {
                    case .continuousAuto: true
                    case .locked: capabilities.supportsExposureLock
                    case .manual: capabilities.supportsManualExposure
                    }
                },
                selection: Binding(
                    get: { currentRemoteSettings.exposureMode },
                    set: { vm.setRemoteCameraExposureMode($0) }
                ),
                label: { $0.displayName }
            ))
            .disabled(!allowsLiveCameraChanges)
            helperText(RemoteCameraControlsCopy.exposureModeHelpText(currentRemoteSettings.exposureMode))
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

        trailingResetButton(.init(
            title: "Reset brightness",
            help: "Set exposure to Auto and brightness to 0",
            action: { vm.resetRemoteCameraExposureBias() }
        ))

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
                label: RemoteCameraControlsCopy.shutterLabel(currentRemoteSettings.shutterDurationSeconds ?? max(minimumShutter, 1.0 / 60.0)),
                isEnabled: capabilities.supportsManualExposure && maximumShutter > minimumShutter,
                onChange: { vm.setRemoteCameraShutterDuration($0) }
            )
        }
    }

    @ViewBuilder
    func remoteWhiteBalanceControls(capabilities: RemoteCameraCapabilities) -> some View {
        if capabilities.supportsWhiteBalanceLock || capabilities.supportsManualWhiteBalance {
            modePicker(.init(
                title: "Color",
                options: RemoteCameraWhiteBalanceMode.allCases.filter { mode in
                    switch mode {
                    case .continuousAuto: true
                    case .locked: capabilities.supportsWhiteBalanceLock
                    case .manual: capabilities.supportsManualWhiteBalance
                    }
                },
                selection: Binding(
                    get: { currentRemoteSettings.whiteBalanceMode },
                    set: { vm.setRemoteCameraWhiteBalanceMode($0) }
                ),
                label: { $0.displayName }
            ))
            .disabled(!allowsLiveCameraChanges)
            helperText(RemoteCameraControlsCopy.whiteBalanceModeHelpText(currentRemoteSettings.whiteBalanceMode))

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
    func stabilizationPicker(capabilities: RemoteCameraCapabilities) -> some View {
        if !capabilities.supportedStabilizationModes.isEmpty {
            modePicker(.init(
                title: "Smoother video",
                options: capabilities.supportedStabilizationModes,
                selection: Binding(
                    get: { currentRemoteSettings.stabilizationMode },
                    set: { vm.setRemoteCameraStabilizationMode($0) }
                ),
                label: RemoteCameraControlsCopy.stabilizationModeLabel
            ))
            .disabled(!allowsFormatChanges || cinematicLocksFormatControls || capabilities.supportedStabilizationModes.count <= 1)
            helperText(RemoteCameraControlsCopy.stabilizationModeHelpText(currentRemoteSettings.stabilizationMode))
        }
    }

    func remoteSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        label: String,
        isEnabled: Bool = true,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let sliderRange = self.sliderRange(.init(range: range, step: step))
        let sliderValue = min(sliderRange.upperBound, max(sliderRange.lowerBound, value))
        return VStack(alignment: .leading, spacing: 5) {
            sliderHeader(.init(title: title, value: label))
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

    var resetImageControlsButton: some View {
        trailingResetButton(.init(
            title: "Auto image",
            help: "Reset focus, brightness, and color to auto",
            action: { vm.resetRemoteCameraImageSettings() }
        ))
    }

    private struct ResetButton {
        let title: String
        let help: String
        let action: () -> Void
    }

    private func trailingResetButton(_ button: ResetButton) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: button.action) {
                Label(button.title, systemImage: "sun.max")
                    .font(BlitzType.captionEmphasis)
            }
            .blitzButton(.secondary)
            .controlSize(.small)
            .disabled(vm.selectedRemoteCameraCapabilities == nil)
            .pointingHandCursor()
            .help(button.help)
        }
    }
}
