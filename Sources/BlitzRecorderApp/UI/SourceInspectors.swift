import SwiftUI

struct TransparentWebcamToggle: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        Toggle(isOn: Binding(
            get: { vm.settings.removesCameraBackgroundAfterRecording },
            set: { vm.setCameraBackgroundRemovalAfterRecording($0) }
        )) {
            Text("Remove background")
        }
        .toggleStyle(.blitzSwitch)
        .disabled(vm.state != .idle || !enabled)
        .help("Remove the camera background after recording")
    }

}

struct ScreenSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if enabled && vm.hasActiveScreenPickerSelection {
                if vm.supportsScreenWindowScaling {
                    ScreenSourceFramingControl(vm: vm, enabled: enabled)
                } else {
                    Button(action: vm.pickScreen) {
                        Label("Choose a window for vertical video", systemImage: "macwindow")
                            .frame(maxWidth: .infinity)
                    }
                    .blitzButton(.secondary)
                    ScreenContentModeControl(vm: vm, enabled: enabled)
                }
            } else {
                Button(action: vm.pickScreen) {
                    Label(vm.screenPickActionTitle, systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.secondary)
                .disabled(!enabled)
            }
        }
    }
}

struct ScreenContentModeControl: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SourceFramingPicker(selection: Binding(
                get: { vm.settings.screenContentMode },
                set: { vm.setScreenContentMode($0) }
            ))
            .disabled(!enabled || !vm.canEditScene)

            if vm.settings.screenContentMode == .fill {
                Button {
                    vm.beginScreenCropMode()
                } label: {
                    Label("Reposition", systemImage: "hand.draw.fill")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.secondary)
                .disabled(!enabled || !vm.canEditScene)
                .pointingHandCursor()
                .help("Drag and resize the visible screen area on the preview")
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
                    .frame(maxWidth: .infinity)
            }
            .blitzButton(.secondary)
            .help("Resize the selected window to this scene so its whole width and height stay visible.")

            BlitzInspectorSlider(configuration: .init(
                title: "Text size",
                value: Binding(
                    get: { Double(vm.targetWindowZoom) },
                    set: { vm.setTargetWindowZoom(CGFloat($0)) }
                ),
                range: 0.5...2,
                step: 0.05,
                valueLabel: "\(Int((vm.targetWindowZoom * 100).rounded()))%",
                onEditingChanged: { if !$0 { vm.applyTargetWindowZoom() } },
                onReset: vm.resetTargetWindowZoom
            ))
            .disabled(!vm.hasAccessibilityAccessForWindowControls)
            .help("Resize the source window so its content looks bigger or smaller. The screen frame in your scene stays put.")
        }
        .disabled(!enabled || !vm.canEditScene || vm.isScreenCropModeEnabled)
    }
}

struct CameraSourceInspector: View {
    @Bindable var vm: RecorderViewModel
    let enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(enabled ? BlitzUI.supportingText : BlitzUI.tertiaryText)
                        .lineLimit(1)
                    Text("Change camera controls in Settings (Cmd+,).")
                        .font(BlitzType.footnote)
                        .foregroundStyle(enabled ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(BlitzType.glyph(9))
                    .foregroundStyle(enabled ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius))
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .disabled(!enabled)
        .pointingHandCursor()
        .help("Open iPhone camera settings. You can also use Cmd+, then Devices.")
    }
}

struct AudioSourceInspector: View {
    let source: CaptureSource
    let levels: TrackLevels
    @Binding var gain: Double
    @Bindable var vm: RecorderViewModel

    private var enabled: Bool { vm.settings.enabledSources.contains(source) }
    private var gainLabel: String { "\(Int((gain * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlitzLevelMeter(levels: levels, active: enabled)
                .frame(height: 22)
                .opacity(enabled ? 1 : 0.3)
                .accessibilityHidden(true)

            BlitzInspectorSlider(configuration: .init(
                title: "Volume",
                value: $gain,
                range: 0...2,
                step: 0.01,
                valueLabel: gainLabel,
                onEditingChanged: { _ in },
                onReset: { gain = 1 }
            ))
            .disabled(vm.state != .idle || !enabled)
            .accessibilityLabel(source == .microphone ? "Microphone volume" : "Mac audio volume")
        }
    }
}

private func inspectorIcon(_ icon: String, enabled: Bool) -> some View {
    Image(systemName: icon)
        .font(BlitzType.glyph(10))
        .foregroundStyle(enabled ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
        .frame(width: 20, height: 20)
        .background(enabled ? BlitzUI.hoverFill : BlitzUI.cardFill, in: .rect(cornerRadius: 6))
}
