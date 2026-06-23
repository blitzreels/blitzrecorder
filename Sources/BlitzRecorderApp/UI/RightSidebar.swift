import BlitzRecorderCore
import SwiftUI

struct CameraCropControls: View {
    @Bindable var vm: RecorderViewModel

    private let mint = BlitzUI.mint

    private var disabled: Bool {
        !vm.isSourceConfigured(.camera) || !vm.canEditCameraCrop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.isCameraCropModeEnabled {
                cropActiveNotice
            } else {
                if vm.isRemoteCameraSelected {
                    RemoteCameraOrientationControl(vm: vm)
                }

                CameraInsetFrameControls(vm: vm)

                CameraInspectorSliderRow(
                    title: "Zoom",
                    value: Binding(
                        get: { cropZoom },
                        set: { vm.setCameraCropZoom(CGFloat($0)) }
                    ),
                    range: 0...0.75
                )
                .help("Zoom into the camera image")

                cropActions
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var cropActiveNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "crop")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mint)
            Text("Cropping on canvas")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(mint.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    private var cropActions: some View {
        HStack(spacing: 8) {
            Button {
                vm.beginCameraCropMode()
            } label: {
                Label("Free crop", systemImage: "viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .pointingHandCursor()
            .help("Edit the camera crop on the live canvas")

            Button {
                vm.resetCameraCrop()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .disabled(isCentered)
            .pointingHandCursor()
            .help("Reset camera crop")
        }
    }

    private var isCentered: Bool {
        vm.settings.cameraCropAmount.x < 0.001 && vm.settings.cameraCropAmount.y < 0.001
            && abs(vm.settings.cameraCropPosition.x) < 0.001 && abs(vm.settings.cameraCropPosition.y) < 0.001
    }

    private var cropZoom: Double {
        Double(max(vm.settings.cameraCropAmount.x, vm.settings.cameraCropAmount.y))
    }
}

struct CameraInsetFrameControls: View {
    @Bindable var vm: RecorderViewModel

    private var disabled: Bool {
        !vm.isSourceConfigured(.camera) || !vm.canEditScene
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CameraInspectorRow(title: "Position") {
                Picker("Position", selection: alignmentSelection) {
                    ForEach(CameraInsetAlignment.allCases, id: \.self) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .help("Place the camera in the bottom left or bottom right corner")

            CameraInspectorRow(title: "Shape") {
                Picker("Shape", selection: shapeSelection) {
                    ForEach(CameraInsetShape.allCases, id: \.self) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .help("Camera frame shape")

            CameraInspectorSliderRow(
                title: "Size",
                value: Binding(
                    get: { vm.cameraInsetSize },
                    set: { vm.setCameraInsetSize($0) }
                ),
                range: vm.cameraInsetSizeRange,
                step: 0.005
            )
            .help("Camera frame size — the frame keeps the camera's real aspect ratio")

            CameraInspectorRow(title: "Image") {
                Picker("Image", selection: contentModeSelection) {
                    ForEach(CameraContentMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            .help("Fill the frame edge to edge, or fit the whole camera image")

            Toggle(isOn: shadowSelection) {
                Label("Shadow", systemImage: "square.stack.3d.down.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(BlitzUI.mint)
            .help("Add a soft shadow under the camera")
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var alignmentSelection: Binding<CameraInsetAlignment> {
        Binding(
            get: { vm.cameraInsetAlignment },
            set: { vm.setCameraInsetAlignment($0) }
        )
    }

    private var shapeSelection: Binding<CameraInsetShape> {
        Binding(
            get: { vm.cameraInsetShape },
            set: { vm.setCameraInsetShape($0) }
        )
    }

    private var contentModeSelection: Binding<CameraContentMode> {
        Binding(
            get: { vm.settings.cameraContentMode },
            set: { vm.setCameraContentMode($0) }
        )
    }

    private var shadowSelection: Binding<Bool> {
        Binding(
            get: { vm.settings.cameraShadowEnabled },
            set: { vm.setCameraShadowEnabled($0) }
        )
    }
}

struct CameraInspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 50, alignment: .leading)
            content
        }
    }
}

struct CameraInspectorSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    var body: some View {
        CameraInspectorRow(title: title) {
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .controlSize(.small)
            .tint(BlitzUI.mint)

            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 34, alignment: .trailing)
        }
    }
}

struct RemoteCameraOrientationControl: View {
    @Bindable var vm: RecorderViewModel
    var usesPanelBackground = false

    private var rotationDegrees: Int {
        RemoteCameraSettings.normalizedRotationDegrees(vm.selectedRemoteCameraRotationDegrees)
    }

    private var supportedRotationDegrees: [Int] {
        let supported = vm.selectedRemoteCameraSupportedRotationDegrees
        let canonical = [0, 90, 180, 270].filter { supported.contains($0) }
        return canonical.isEmpty ? [0, 90, 180, 270] : canonical
    }

    private var isEnabled: Bool {
        vm.isRemoteCameraSelected && vm.state == .idle && supportedRotationDegrees.count > 1
    }

    private var usesAutomaticRotation: Bool {
        vm.selectedRemoteCameraUsesAutomaticRotation
    }

    private var isPortraitRotation: Bool {
        RemoteCameraSettingsResolver.isPortraitRotation(rotationDegrees)
    }

    private var orientationLabel: String {
        let prefix = usesAutomaticRotation ? "Auto" : "Manual"
        return isPortraitRotation ? "\(prefix) Portrait" : "\(prefix) Landscape"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isPortraitRotation ? "rectangle.portrait" : "rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.76 : 0.42))
                    .frame(width: 18, height: 18)
                Text("Orientation")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.72 : 0.48))
                Spacer(minLength: 0)
                Text(orientationLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.74 : 0.42))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 6))
            }

            HStack(spacing: 7) {
                orientationButton("Auto", systemImage: "iphone.gen3") {
                    vm.setRemoteCameraAutomaticRotation(true)
                }
                .background(usesAutomaticRotation ? BlitzUI.mint.opacity(0.16) : Color.clear, in: .rect(cornerRadius: 8))
                orientationButton("Left", systemImage: "rotate.left") {
                    rotate(by: -1)
                }
                orientationButton("Right", systemImage: "rotate.right") {
                    rotate(by: 1)
                }
                orientationButton("Flip", systemImage: "arrow.up.and.down") {
                    flip()
                }
            }
        }
        .padding(usesPanelBackground ? 10 : 0)
        .background(usesPanelBackground ? Color.white.opacity(0.055) : Color.clear, in: .rect(cornerRadius: 10))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private func orientationButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .help("\(title) iPhone feed")
    }

    private func rotate(by step: Int) {
        let next = nextRotation(step: step)
        vm.setRemoteCameraRotationDegrees(next)
    }

    private func flip() {
        let flipped = RemoteCameraSettings.normalizedRotationDegrees(rotationDegrees + 180)
        if supportedRotationDegrees.contains(flipped) {
            vm.setRemoteCameraRotationDegrees(flipped)
        } else {
            rotate(by: 2)
        }
    }

    private func nextRotation(step: Int) -> Int {
        let supported = supportedRotationDegrees
        guard !supported.isEmpty else { return rotationDegrees }
        let currentIndex = supported.firstIndex(of: rotationDegrees) ?? 0
        let nextIndex = (currentIndex + step % supported.count + supported.count) % supported.count
        return supported[nextIndex]
    }
}

struct OverlayToggleRow: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 0.85 : 0.45))
                .frame(width: 18, height: 18)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isOn ? 0.95 : 0.55))
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
        .pointingHandCursor()
    }
}

struct SafeZonePickerRow: View {
    @Binding var selected: SocialVideoSafeZone
    let disabled: Bool

    @State private var popoverOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.inset.filled")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected == .none ? 0.45 : 0.85))
                    .frame(width: 18, height: 18)
                Text("Safe zone")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(selected == .none ? 0.55 : 0.95))
                Spacer(minLength: 0)
            }

            Button {
                popoverOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(disabled ? "Portrait only" : selected.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .blitzGlassButton()
            .controlSize(.small)
            .disabled(disabled)
            .pointingHandCursor()
            .popover(isPresented: $popoverOpen, arrowEdge: .top) {
                SafeZonePopover(selected: $selected, isOpen: $popoverOpen)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(disabled ? 0.62 : 1)
    }
}

private struct SafeZonePopover: View {
    @Binding var selected: SocialVideoSafeZone
    @Binding var isOpen: Bool

    private let mint = BlitzUI.mint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAFE ZONE PRESET")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))

            VStack(spacing: 4) {
                ForEach(SocialVideoSafeZone.allCases, id: \.self) { zone in
                    row(for: zone)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .foregroundStyle(.white)
    }

    private func row(for zone: SocialVideoSafeZone) -> some View {
        let isSelected = selected == zone
        return Button {
            selected = zone
            isOpen = false
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                    Image(systemName: zone.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? mint : .white.opacity(0.85))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(zone.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(zone.subtitle)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(mint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .blitzGlassButton()
        .tint(isSelected ? mint.opacity(0.22) : .clear)
        .pointingHandCursor()
    }
}
