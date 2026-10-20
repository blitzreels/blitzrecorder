import BlitzRecorderCore
import SwiftUI

struct RemoteCameraPage: View {
    @Bindable var vm: RecorderViewModel
    @State private var showsDirectConnection = false
    @State private var showsDevicePicker = false
    @FocusState private var focusedField: ConnectionField?

    private enum ConnectionField: Hashable {
        case address
        case port
    }

    private struct SetupStep {
        let number: Int
        let title: String
        let detail: String
    }

    private var selectedDevice: RemoteCameraDeviceSummary? {
        vm.remoteCameraDeviceSummaries.first { $0.isSelected }
    }

    private var canConnect: Bool {
        vm.state == .idle
            && !vm.remoteCameraPreview.directRemoteCameraHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !vm.remoteCameraPreview.directRemoteCameraPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(.init(
                    title: "iPhone Camera",
                    detail: "Pair your iPhone, check its connection, and adjust the camera.",
                    status: nil
                ))

                if vm.isRemoteCameraSelected {
                    connectedSummary
                    if showsDevicePicker { nearbyDevices }
                    cameraWorkspace
                } else {
                    setupSummary
                    setupGuide
                    nearbyDevices
                }

                directConnection
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .onAppear { vm.startRemoteCameraDiscovery() }
    }

    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            BlitzAdaptiveRow(.init(minimumContentWidth: 320)) {
                HStack(spacing: 18) {
                    phoneIcon
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A better camera. Right beside you.")
                            .font(BlitzType.title)
                        Text("Record on your iPhone. Frame the shot and control the camera from your Mac.")
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Link(destination: BlitzRecorderProductIdentity.companionInstallURL) {
                    Label("Get iPhone app", systemImage: "arrow.up.right")
                }
                .blitzButton(.secondary)
                .help("Open \(BlitzRecorderProductIdentity.companionDisplayName)")
            }

            if vm.settings.enabledSources.contains(.camera) {
                SettingsRowDivider()
                HStack(spacing: 8) {
                    Image(systemName: "video")
                    Text("Recorder camera")
                    Spacer(minLength: 8)
                    Text(vm.selectedCameraDisplayName)
                        .foregroundStyle(BlitzUI.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                Text("Pairing below uses the BlitzRecorder Camera app, separate from macOS Continuity Camera.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -8)
            }
        }
        .settingsSurface()
    }

    private var phoneIcon: some View {
        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
            .font(BlitzType.glyph(30))
            .foregroundStyle(BlitzUI.accent)
            .frame(width: 64, height: 64)
            .background(BlitzUI.accent.opacity(0.08), in: .rect(cornerRadius: BlitzUI.surfaceRadius))
    }

    private var setupGuide: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20)], alignment: .leading, spacing: 20) {
            setupStep(.init(number: 1, title: "Open the app", detail: "Launch BlitzRecorder Camera on your iPhone."))
            setupStep(.init(number: 2, title: "Use the same Wi-Fi", detail: "Keep your iPhone and Mac on one network."))
            setupStep(.init(number: 3, title: "Pair below", detail: "Select your iPhone and enter its six-digit code."))
        }
        .settingsSurface()
    }

    private func setupStep(_ step: SetupStep) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(step.number)")
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 24, height: 24)
                .background(BlitzUI.quietFill, in: .circle)
            Text(step.title)
                .font(BlitzType.label)
            Text(step.detail)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var nearbyDevices: some View {
        VStack(alignment: .leading, spacing: 14) {
            BlitzAdaptiveRow() {
                Text("Nearby iPhones")
                    .font(BlitzType.section)
                Button {
                    vm.startRemoteCameraDiscovery()
                } label: {
                    Label("Search again", systemImage: "arrow.clockwise")
                }
                .blitzButton(.secondary)
                .disabled(vm.state != .idle)
            }

            if vm.remoteCameraDeviceSummaries.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "wifi")
                        .font(BlitzType.glyph(22))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Waiting for your iPhone")
                            .font(BlitzType.callout)
                        Text("Keep the iPhone app open. Your device will appear here automatically.")
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.remoteCameraDeviceSummaries.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { SettingsRowDivider() }
                        deviceRow(device)
                    }
                }
            }
        }
        .settingsSurface()
    }

    private func deviceRow(_ device: RemoteCameraDeviceSummary) -> some View {
        BlitzAdaptiveRow() {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(BlitzType.glyph(21))
                    .foregroundStyle(device.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                    .frame(width: 36, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(BlitzType.callout)
                    Text(device.detail)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(2)
                }
            }
            SettingsStatusBadge(configuration: .init(
                title: device.status,
                tone: device.isReady ? .ready : .muted
            ))
            if !device.isSelected {
                Button(device.isTrusted ? "Use camera" : "Pair…") {
                    vm.setCamera(device.cameraID)
                }
                .blitzButton(.secondary)
                .disabled(vm.state != .idle)
                .help("Use \(device.name) as the recording camera")
            }
        }
        .padding(.vertical, 12)
    }

    private var connectedSummary: some View {
        BlitzAdaptiveRow(.init(minimumContentWidth: 320)) {
            HStack(spacing: 16) {
                phoneIcon
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.selectedRemoteCameraName ?? "iPhone camera")
                        .font(BlitzType.title)
                    Text(vm.selectedRemoteCameraDeviceDescription)
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .lineLimit(2)
                    SettingsStatusBadge(configuration: .init(
                        title: vm.selectedRemoteCameraStatus ?? "Waiting for connection",
                        tone: selectedDevice?.isReady == true ? .ready : .warning
                    ))
                }
            }
            Button(showsDevicePicker ? "Hide devices" : "Change iPhone") {
                showsDevicePicker.toggle()
            }
            .blitzButton(.secondary)
            .disabled(vm.state != .idle)
        }
        .settingsSurface()
    }

    private var cameraWorkspace: some View {
        BlitzAdaptiveRow(.init(minimumContentWidth: 260, spacing: 20)) {
            cameraPreview
            RemoteCameraControlsPane(vm: vm, showsStatusHeader: false)
                .frame(width: 280, alignment: .topLeading)
        }
        .settingsSurface()
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Camera preview")
                .font(BlitzType.section)
            ZStack {
                Color.black
                CameraPreviewRepresentable(view: vm.remoteCameraPreviewSurface)
                    .aspectRatio(vm.remoteCameraPreview.remoteCameraPreviewAspectRatio, contentMode: .fit)
                if !vm.remoteCameraPreview.hasRemoteCameraPreviewImage {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.gen3")
                            .font(BlitzType.glyph(28))
                        Text("Waiting for video")
                            .font(BlitzType.label)
                        Text("Keep the iPhone app open.")
                            .font(BlitzType.caption)
                    }
                    .foregroundStyle(BlitzUI.onMediaSecondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.85))
                }
            }
            .frame(height: 310)
            .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
            Text(vm.selectedRemoteCameraReviewStatus)
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
            RemoteCameraOrientationControl(vm: vm, usesPanelBackground: true)
        }
    }

    private var directConnection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showsDirectConnection.toggle()
                if showsDirectConnection { focusedField = .address }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .foregroundStyle(BlitzUI.secondaryText)
                    Text("Connect by address")
                        .font(BlitzType.label)
                    Spacer()
                    Image(systemName: showsDirectConnection ? "chevron.up" : "chevron.down")
                        .font(BlitzType.glyph(10))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityValue(showsDirectConnection ? "Expanded" : "Collapsed")

            if showsDirectConnection {
                Text("If discovery cannot find your iPhone, enter the address and port shown in its app.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzAdaptiveRow(.init(minimumContentWidth: 200)) {
                    connectionField(.address)
                    connectionField(.port)
                        .frame(width: 90)
                    Button {
                        vm.connectDirectRemoteCamera()
                    } label: {
                        Label("Connect", systemImage: "arrow.right")
                    }
                    .blitzButton(.secondary)
                    .disabled(!canConnect)
                    .frame(height: 36)
                }
            }
        }
        .settingsSurface()
    }

    private func connectionField(_ field: ConnectionField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            BlitzUI.sectionLabel(field == .address ? "iPhone address" : "Port")
            TextField(
                field == .address ? "192.168.1.10" : "Port",
                text: field == .address
                    ? Binding(
                        get: { vm.remoteCameraPreview.directRemoteCameraHost },
                        set: { vm.remoteCameraPreview.directRemoteCameraHost = $0 }
                    )
                    : Binding(
                        get: { vm.remoteCameraPreview.directRemoteCameraPort },
                        set: { vm.remoteCameraPreview.directRemoteCameraPort = $0 }
                    )
            )
            .textFieldStyle(.plain)
            .font(BlitzType.body.monospaced())
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius)
                    .strokeBorder(focusedField == field ? BlitzUI.accent.opacity(0.6) : BlitzUI.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .focused($focusedField, equals: field)
            .disabled(vm.state != .idle)
            .accessibilityLabel(field == .address ? "iPhone address" : "Port")
            .onSubmit {
                if canConnect { vm.connectDirectRemoteCamera() }
            }
        }
    }
}
