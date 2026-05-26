import SwiftUI

struct RightSidebar: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        scenePane
            .frame(width: 240)
            .foregroundStyle(.white)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var scenePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if vm.selectedLayer == .camera && vm.isSelectedLayerEnabled {
                    section("Crop") {
                        CameraCropControls(vm: vm)
                    }
                }

                section("Overlays") {
                    VStack(spacing: 0) {
                        OverlayToggleRow(
                            symbol: "cursorarrow",
                            title: "Show cursor",
                            isOn: Binding(
                                get: { vm.settings.includeCursor },
                                set: { vm.setCursorIncluded($0) }
                            )
                        )
                        Divider().background(.white.opacity(0.08)).padding(.horizontal, 12)
                        OverlayToggleRow(
                            symbol: "grid",
                            title: "Rule of thirds",
                            isOn: Binding(
                                get: { vm.settings.showsRuleOfThirdsOverlay },
                                set: { vm.setRuleOfThirds($0) }
                            )
                        )
                        Divider().background(.white.opacity(0.08)).padding(.horizontal, 12)
                        SafeZonePickerRow(
                            selected: Binding(
                                get: { vm.settings.socialSafeZoneOverlay },
                                set: { vm.setSocialSafeZoneOverlay($0) }
                            ),
                            disabled: vm.settings.layout != .vertical
                        )
                    }
                    .background(Color.white.opacity(0.055), in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .disabled(vm.state != .idle && title != "Target window")
        }
    }
}

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
                .buttonStyle(.glass)
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
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!vm.isCameraCropModeEnabled && isCentered)
                .pointingHandCursor()
                .help("Reset camera crop")
            }

            if vm.isCameraCropModeEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(mint)
                            .frame(width: 6, height: 6)
                        Text("Cropping camera")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)

                    HStack(spacing: 8) {
                        Button {
                            vm.applyCameraCropMode()
                        } label: {
                            Label("Done cropping", systemImage: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black.opacity(0.88))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(mint, in: .rect(cornerRadius: 8))
                                .shadow(color: mint.opacity(0.28), radius: 8, y: 2)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help("Apply the crop")

                        Button {
                            vm.cancelCameraCropMode()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(width: 28, height: 28)
                                .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help("Cancel crop changes")
                    }
                }
            } else {
                Button {
                    vm.beginCameraCropMode()
                } label: {
                    Label("Edit crop", systemImage: "viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.glass)
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
            .buttonStyle(.glass)
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
        .buttonStyle(.glass)
        .tint(isSelected ? mint.opacity(0.22) : .clear)
        .pointingHandCursor()
    }
}
