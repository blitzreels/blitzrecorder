import SwiftUI

struct CameraCropControls: View {
    @Bindable var vm: RecorderViewModel

    private let mint = Color(red: 0.09, green: 1.0, blue: 0.65)

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
                    vm.centerCameraCrop()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .blitzGlassButton()
                .controlSize(.small)
                .disabled(!vm.isCameraCropModeEnabled && positionIsCentered)
                .pointingHandCursor()
                .help("Center crop")

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
                cropPresetControls

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
        .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(vm.isCameraCropModeEnabled ? mint.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var isCentered: Bool {
        vm.settings.cameraCropAmount.x < 0.001 && vm.settings.cameraCropAmount.y < 0.001
            && abs(vm.settings.cameraCropPosition.x) < 0.001 && abs(vm.settings.cameraCropPosition.y) < 0.001
    }

    private var positionIsCentered: Bool {
        abs(vm.settings.cameraCropPosition.x) < 0.001 && abs(vm.settings.cameraCropPosition.y) < 0.001
    }

    private var cropZoom: Double {
        Double(max(vm.settings.cameraCropAmount.x, vm.settings.cameraCropAmount.y))
    }

    private var cropPresetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                cropPresetButton("Fit", icon: "rectangle", amount: .zero)
                cropPresetButton("Med", icon: "plus.magnifyingglass", amount: CGPoint(x: 0.22, y: 0.22))
                cropPresetButton("Tight", icon: "viewfinder", amount: CGPoint(x: 0.42, y: 0.42))
            }

            cropSlider(
                title: "Zoom",
                value: Binding(
                    get: { cropZoom },
                    set: { vm.setCameraCropZoom(CGFloat($0)) }
                ),
                range: 0...0.75
            )
            cropSlider(
                title: "X",
                value: Binding(
                    get: { Double(vm.settings.cameraCropPosition.x) },
                    set: { vm.setCameraCropPanX(CGFloat($0)) }
                ),
                range: -1...1
            )
            cropSlider(
                title: "Y",
                value: Binding(
                    get: { Double(vm.settings.cameraCropPosition.y) },
                    set: { vm.setCameraCropPanY(CGFloat($0)) }
                ),
                range: -1...1
            )
        }
    }

    private func cropPresetButton(_ title: String, icon: String, amount: CGPoint) -> some View {
        Button {
            vm.setCameraCropPreset(amount: amount, position: .zero)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .blitzGlassButton()
        .controlSize(.small)
        .pointingHandCursor()
        .help(title)
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

    private let mint = Color(red: 0.09, green: 1.0, blue: 0.65)

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
