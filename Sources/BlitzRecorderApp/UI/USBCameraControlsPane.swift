import SwiftUI

struct USBCameraControlsPane: View {
    @Bindable var vm: RecorderViewModel
    @State private var rollDraft: Double?

    private var model: USBCameraControlsModel { vm.coordinator.usbCameraControls }
    private var framing: [USBCameraControl] { model.visibleControls.filter(\.kind.isFraming) }
    private var canReset: Bool { model.controls.contains { !$0.kind.movesCamera } }
    private var hasGimbal: Bool { model.controls.contains { $0.kind.movesCamera } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                connection
                if !framing.isEmpty {
                    rows(framing.filter { !$0.kind.movesCamera })
                    if hasGimbal { gimbal }
                }
                group(.init(title: "Focus", symbol: "scope", kinds: [.autoFocus, .focus]))
                group(.init(title: "Exposure", symbol: "sun.max", kinds: [.autoExposure, .exposure, .gain]))
                group(.init(title: "White balance", symbol: "thermometer.medium", kinds: [.autoWhiteBalance, .whiteBalance]))
                group(.init(title: "Image", symbol: "slider.horizontal.3", kinds: [.brightness, .contrast, .saturation, .sharpness]))
                if model.isApplying {
                    Text("Applying to camera…").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                if let error = model.controlError {
                    Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                }
            }
            .padding(.bottom, 12)
            if canReset {
                Divider()
                HStack {
                    Button("Reset image settings", action: model.reset)
                        .blitzButton(.quiet).controlSize(.small)
                        .help("Restore zoom and image defaults without changing pan or tilt")
                    Spacer()
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let incoming = vm.cameraIncomingSize {
                    Text(CameraDeliverySnapshot.label(incoming))
                        .font(BlitzType.caption.monospacedDigit())
                        .foregroundStyle(BlitzUI.secondaryText)
                        .accessibilityLabel("Incoming resolution: \(CameraDeliverySnapshot.label(incoming))")
                        .help("Resolution received from the camera")
                } else {
                    Text("Waiting for camera…")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                Spacer(minLength: 8)
                Button("Refresh") { Task { await model.refresh() } }
                    .blitzButton(.quiet).controlSize(.small)
                    .help("Read the current settings from the camera")
            }
            if let incoming = vm.cameraIncomingSize, let picture = vm.cameraUsablePictureSize {
                if incoming != picture {
                    signalRow(.init(title: "Usable picture", value: CameraDeliverySnapshot.label(picture)))
                }
                if let shortfall = vm.cameraDeliveryShortfall {
                    signalRow(.init(title: "Available format", value: CameraDeliverySnapshot.label(shortfall.bestSize)))
                    Label("Lower resolution received", systemImage: "exclamationmark.triangle")
                        .font(BlitzType.captionEmphasis).foregroundStyle(BlitzUI.warning)
                    Text(incoming != picture
                         ? "The incoming frame contains black bars. Changing the canvas or crop does not increase its detail."
                         : "The incoming frame is smaller than the camera’s available format.")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reconnect camera") { vm.onRetryCameraPreview?() }
                        .blitzButton(.secondary).controlSize(.small)
                        .disabled(vm.state != .idle)
                        .help("Restart camera capture and request its best supported format")
                }
            }
        }
    }

    private struct SignalRow {
        let title: String
        let value: String
    }

    private func signalRow(_ row: SignalRow) -> some View {
        HStack {
            Text(row.title).foregroundStyle(BlitzUI.secondaryText)
            Spacer()
            Text(row.value).monospacedDigit().foregroundStyle(BlitzUI.primaryText)
        }
        .font(BlitzType.label)
    }

    private struct SectionTitle {
        let title: String
        let symbol: String
    }

    private struct SectionContent<Content: View> {
        let title: SectionTitle
        @ViewBuilder let content: () -> Content
    }

    private func section<Content: View>(_ request: SectionContent<Content>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(request.title.title, systemImage: request.title.symbol)
                .font(BlitzType.section).foregroundStyle(BlitzUI.primaryText)
            request.content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct ControlGroup {
        let title: String
        let symbol: String
        let kinds: [USBCameraControlKind]
    }

    @ViewBuilder private func group(_ group: ControlGroup) -> some View {
        let controls = model.visibleControls.filter { group.kinds.contains($0.kind) }
        if !controls.isEmpty {
            section(.init(title: .init(title: group.title, symbol: group.symbol), content: { rows(controls) }))
        }
    }

    private var gimbal: some View {
        VStack(spacing: 6) {
            direction(.init(kind: .tilt, delta: 5, title: "Tilt up", symbol: "chevron.up"))
            HStack(spacing: 6) {
                direction(.init(kind: .pan, delta: -5, title: "Pan left", symbol: "chevron.left"))
                Button(action: model.centerOrTurnAround) {
                    Image(systemName: "scope").frame(width: 28)
                }
                .blitzButton(.secondary).controlSize(.regular)
                .accessibilityLabel("Center the gimbal, or turn it around")
                .help("Center the gimbal. Press again to turn it around 180°")
                direction(.init(kind: .pan, delta: 5, title: "Pan right", symbol: "chevron.right"))
            }
            direction(.init(kind: .tilt, delta: -5, title: "Tilt down", symbol: "chevron.down"))
            HStack(spacing: 16) {
                ForEach(model.controls.filter { $0.kind.movesCamera }) { control in
                    Text("\(control.kind.title) \(control.kind.label(control.value))")
                }
            }
            .font(BlitzType.caption.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .task(id: model.loadedCameraID) {
            while !Task.isCancelled {
                await model.refreshGimbalPosition()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private struct Direction {
        let kind: USBCameraControlKind
        let delta: Int
        let title: String
        let symbol: String
    }

    private func direction(_ direction: Direction) -> some View {
        let control = model.controls.first { $0.kind == direction.kind }
        return Button {
            guard control != nil else { return }
            model.move(.init(kind: direction.kind, delta: direction.delta * 3_600))
        } label: {
            Image(systemName: direction.symbol).frame(width: 28)
        }
        .blitzButton(.secondary).controlSize(.regular)
        .disabled(control == nil)
        .accessibilityLabel(direction.title)
        .help("\(direction.title) by 5°")
    }

    private func rows(_ controls: [USBCameraControl]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(controls) { control in
                if control.kind.isToggle {
                    Toggle(control.kind.title, isOn: Binding(
                        get: { control.value == 1 },
                        set: { model.setValue($0 ? 1 : 0, for: control.kind) }
                    ))
                    .toggleStyle(.blitzSwitch)
                } else {
                    BlitzInspectorSlider(configuration: .init(
                        title: control.kind == .roll ? "Gimbal roll" : control.kind.title,
                        value: Binding(
                            get: { control.kind == .roll ? rollDraft ?? Double(control.value) : Double(control.value) },
                            set: {
                                if control.kind == .roll { rollDraft = $0 }
                                else { model.setValue(Int($0.rounded()), for: control.kind) }
                            }
                        ),
                        range: Double(control.range.lowerBound)...Double(control.range.upperBound),
                        step: Double(control.step),
                        valueLabel: control.kind.label(control.kind == .roll ? Int(rollDraft ?? Double(control.value)) : control.value),
                        onEditingChanged: { editing in
                            if !editing, control.kind == .roll, let rollDraft {
                                model.setValue(Int(rollDraft.rounded()), for: .roll)
                                self.rollDraft = nil
                            }
                        },
                        onReset: { model.setValue(control.defaultValue, for: control.kind) }
                    ))
                    .help(control.kind == .roll
                          ? "Rotate the gimbal. 0° is the camera’s reported setting, not a saved position."
                          : control.kind.title)
                }
            }
        }
    }
}

struct USBCameraControlsButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsControls = false

    private var model: USBCameraControlsModel { vm.coordinator.usbCameraControls }

    var body: some View {
        if !model.controls.isEmpty {
            BlitzInspectorDisclosure(configuration: .init(
                title: "Camera settings",
                detail: nil,
                isExpanded: $showsControls,
                content: { USBCameraControlsPane(vm: vm) }
            ))
            .controlSize(.small)
            .onChange(of: showsControls) { if showsControls { Task { await model.refresh() } } }
        }
    }
}

extension RecorderViewModel {
    var usbControllableCameraID: String? {
        isRemoteCameraSelected || !isSourceConfigured(.camera) ? nil : coordinator.mainLocalCameraDeviceID
    }
}
