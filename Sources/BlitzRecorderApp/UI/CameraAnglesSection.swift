import AppKit
import AVFoundation
import SwiftUI

/// Extra Mac cameras under the Camera row. Each angle shows live and records its own file in the take.
struct CameraAnglesSection: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        if !vm.cameraAngles.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(vm.cameraAngles) { angle in
                    let microphone = vm.pairedMicrophone(cameraDeviceID: angle.deviceID)
                    let microphoneTitle = microphone.flatMap { vm.recordingMicrophoneTitle(deviceID: $0.id) }
                    CameraAngleRow(angle: angle, microphoneTitle: microphoneTitle, vm: vm)
                    if let microphone, microphoneTitle == nil, vm.state == .idle {
                        Button("Use its microphone") { vm.addMicrophoneTrack(microphone.id) }
                            .blitzButton(.quiet)
                            .controlSize(.small)
                            .help("Record \(microphone.name) as its own microphone track")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Each angle saves as its own video. Scenes for it appear in the strip under the preview.")
        }
    }
}

/// "Add camera", always under the camera: records another camera at the same time, as a second angle. With
/// no other camera available it says why, and how to connect one.
struct CameraAngleAddButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsPicker = false

    var body: some View {
        if vm.isSourceConfigured(.camera) {
            Button {
                showsPicker = true
            } label: {
                Label("Add camera", systemImage: "plus")
                    .font(BlitzType.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .blitzButton(.quiet)
            .controlSize(.small)
            .disabled(vm.state != .idle)
            .help(vm.state == .idle ? "Record another camera at the same time, as a second angle" : "Cameras are locked while recording")
            .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
                if vm.cameraAngleCandidates.isEmpty {
                    NoSecondCameraHelp(vm: vm) { showsPicker = false }
                } else {
                    BlitzSourcePickerPopover(model: CameraAnglePickerModel.add(vm: vm)) { showsPicker = false }
                }
            }
            .onChange(of: vm.state) { if vm.state != .idle { showsPicker = false } }
        }
    }
}

/// Why there is no second camera to add yet, and how to get one.
private struct NoSecondCameraHelp: View {
    @Bindable var vm: RecorderViewModel
    let dismiss: () -> Void
    @State private var camerasInDriveMode: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a second camera")
                .font(BlitzType.headline)
                .foregroundStyle(BlitzUI.primaryText)
            if let name = camerasInDriveMode.first {
                Text("\(name) is plugged in as a drive, so it can't film yet. On the camera, choose Webcam mode. It appears here a few seconds later.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Connect another camera to this Mac: a USB webcam, an action camera in webcam mode, or an iPhone with Continuity Camera. Each camera records its own video.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Look again") {
                    Task {
                        await vm.refreshSources()
                        camerasInDriveMode = USBCameraMode.camerasNotInWebcamMode()
                    }
                }
                .blitzButton(.secondary)
                Button("Done", action: dismiss)
                    .blitzButton(.quiet)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
        .task { camerasInDriveMode = USBCameraMode.camerasNotInWebcamMode() }
    }
}

private struct CameraAngleRow: View {
    let angle: CameraAngleItem
    /// The microphone recording this camera's own audio, such as "Microphone 2".
    let microphoneTitle: String?
    @Bindable var vm: RecorderViewModel
    @State private var showsPicker = false

    private var isLocked: Bool { vm.state != .idle }

    var body: some View {
        InputField(configuration: .init(
            value: angle.deviceName,
            track: angle.name,
            tone: angle.isConnected ? .value : .warning,
            isEnabled: !isLocked,
            help: help,
            open: { showsPicker = true },
            isPresented: showsPicker
        )) {
            CameraAngleThumbnail(deviceID: angle.deviceID, isConnected: angle.isConnected, vm: vm)
        }
        .accessibilityLabel(angle.name)
        .contextMenu { BlitzContextMenuItems(entries: menuEntries) }
        .popover(isPresented: $showsPicker, arrowEdge: .trailing) {
            BlitzSourcePickerPopover(model: CameraAnglePickerModel.change(angle: angle, vm: vm)) { showsPicker = false }
        }
        .onChange(of: isLocked) { if isLocked { showsPicker = false } }
    }

    private var help: String {
        if isLocked { return "\(angle.name) is recording" }
        let microphone = microphoneTitle.map { " Its microphone records as \($0)." } ?? ""
        return "Change or remove \(angle.name).\(microphone)"
    }

    private var menuEntries: [BlitzMenuEntry] {
        [.item(BlitzMenuItem(
            title: "Remove \(angle.name)",
            systemImage: "minus.circle",
            isEnabled: !isLocked
        ) { vm.removeCameraAngle(angle.deviceID) })]
    }
}

/// Live picture from one angle's own capture session, the same session that records the take file.
private struct CameraAngleThumbnail: View {
    let deviceID: String
    let isConnected: Bool
    @Bindable var vm: RecorderViewModel
    @State private var layer: AVCaptureVideoPreviewLayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.quaternary)
            if let layer, isConnected, !failed {
                CameraAnglePreviewLayerView(layer: layer)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "video.slash")
                    .font(BlitzType.glyph(12))
                    .foregroundStyle(BlitzUI.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .task(id: TaskKey(deviceID: deviceID, isConnected: isConnected)) {
            layer = nil
            failed = false
            guard isConnected else { return }
            do {
                layer = try await vm.cameraAnglePreviewLayer(deviceID)
            } catch {
                failed = true
            }
        }
        .onDisappear { vm.stopCameraAnglePreview(deviceID) }
    }

    private struct TaskKey: Equatable {
        let deviceID: String
        let isConnected: Bool
    }
}

private struct CameraAnglePreviewLayerView: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.host(layer)
        return view
    }

    func updateNSView(_ view: LayerHostView, context: Context) {
        view.host(layer)
    }

    final class LayerHostView: NSView {
        private var hosted: AVCaptureVideoPreviewLayer?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func host(_ layer: AVCaptureVideoPreviewLayer) {
            guard hosted !== layer else { return }
            hosted?.removeFromSuperlayer()
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer?.addSublayer(layer)
            hosted = layer
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}

@MainActor
private enum CameraAnglePickerModel {
    static func add(vm: RecorderViewModel) -> BlitzSourcePickerModel {
        model(.init(
            title: "Add angle",
            prompt: "Choose a camera for the next angle",
            vm: vm,
            choose: { vm.addCameraAngle($0) },
            actions: []
        ))
    }

    static func change(angle: CameraAngleItem, vm: RecorderViewModel) -> BlitzSourcePickerModel {
        model(.init(
            title: angle.name,
            prompt: "Choose the camera for \(angle.name)",
            vm: vm,
            choose: { vm.replaceCameraAngle(.init(oldDeviceID: angle.deviceID, newDeviceID: $0)) },
            actions: [
                BlitzSourcePickerItem(
                    id: "camera-angle:remove:\(angle.deviceID)",
                    title: "Remove \(angle.name)",
                    subtitle: nil,
                    systemImage: "minus.circle",
                    icon: nil,
                    thumbnail: nil,
                    isSelected: false
                ) { vm.removeCameraAngle(angle.deviceID) }
            ]
        ))
    }

    private struct Request {
        let title: String
        let prompt: String
        let vm: RecorderViewModel
        let choose: (String) -> Void
        let actions: [BlitzSourcePickerItem]
    }

    private static func model(_ request: Request) -> BlitzSourcePickerModel {
        let candidates = request.vm.cameraAngleCandidates
        return BlitzSourcePickerModel(
            title: request.title,
            subtitle: "Mac camera",
            systemImage: BlitzSymbols.camera,
            icon: nil,
            sections: [
                BlitzSourcePickerSection(title: "Cameras", items: candidates.map { item($0, choose: request.choose) })
            ],
            actions: request.actions,
            layout: .list,
            enabled: request.vm.state == .idle,
            prompt: request.prompt,
            refresh: { await request.vm.refreshSources() }
        )
    }

    private static func item(_ option: SourceOption, choose: @escaping (String) -> Void) -> BlitzSourcePickerItem {
        let kind = option.cameraKind ?? .external
        return BlitzSourcePickerItem(
            id: "camera:\(option.id)",
            title: CameraOptionName.plain(option.name),
            subtitle: kind.subtitle,
            systemImage: kind.systemImage,
            icon: nil,
            thumbnail: nil,
            isSelected: false
        ) { choose(option.id) }
    }
}
