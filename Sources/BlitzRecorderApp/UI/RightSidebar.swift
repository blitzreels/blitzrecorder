import BlitzRecorderCore
import SwiftUI

struct CameraCropControls: View {
    @Bindable var vm: RecorderViewModel

    private let mint = BlitzUI.mint

    private var disabled: Bool {
        !vm.isSourceConfigured(.camera) || !vm.canEditCameraCrop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "crop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.4 : 0.82))
                    .frame(width: 18, height: 18)
                Text("Camera crop")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.55 : 0.95))
                Spacer(minLength: 0)
                Button {
                    vm.resetCameraCrop()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .blitzGlassButton()
                .controlSize(.small)
                .disabled(!vm.isCameraCropModeEnabled && isCentered)
                .pointingHandCursor()
                .help("Reset camera crop")
            }

            if !vm.isCameraCropModeEnabled {
                if vm.isRemoteCameraSelected {
                    RemoteCameraOrientationControl(vm: vm)
                }

                cropZoomControl

                Button {
                    vm.beginCameraCropMode()
                } label: {
                    Label("Free crop", systemImage: "viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .blitzGlassButton()
                .controlSize(.small)
                .pointingHandCursor()
                .help("Edit camera crop on the live canvas")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Active crop-edit mode reads from a mint-tinted fill, not a mint outline.
        .background(
            vm.isCameraCropModeEnabled ? mint.opacity(0.12) : Color.white.opacity(0.055),
            in: .rect(cornerRadius: 10)
        )
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var isCentered: Bool {
        vm.settings.cameraCropAmount.x < 0.001 && vm.settings.cameraCropAmount.y < 0.001
            && abs(vm.settings.cameraCropPosition.x) < 0.001 && abs(vm.settings.cameraCropPosition.y) < 0.001
    }

    private var cropZoom: Double {
        Double(max(vm.settings.cameraCropAmount.x, vm.settings.cameraCropAmount.y))
    }

    private var cropZoomControl: some View {
        cropSlider(
            title: "Zoom",
            value: Binding(
                get: { cropZoom },
                set: { vm.setCameraCropZoom(CGFloat($0)) }
            ),
            range: 0...0.75
        )
    }

    private func cropSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 34, alignment: .leading)

            Slider(value: value, in: range)
                .controlSize(.small)
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
