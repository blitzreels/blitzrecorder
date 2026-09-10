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
            && !vm.directRemoteCameraHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !vm.directRemoteCameraPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(.init(
                    title: "iPhone Camera",
                    detail: "Pair your iPhone, check its connection, and adjust the camera.",
                    systemImage: "iphone.gen3",
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
            HStack(spacing: 18) {
                phoneIcon
                VStack(alignment: .leading, spacing: 6) {
                    Text("A better camera. Right beside you.")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Record on your iPhone. Frame the shot and control the camera from your Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
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
                .font(.system(size: 11))
                .foregroundStyle(BlitzUI.secondaryText)
                Text("Pairing below uses the BlitzRecorder Camera app, separate from macOS Continuity Camera.")
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -8)
            }
        }
        .settingsSurface()
    }

    private var phoneIcon: some View {
        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(BlitzUI.mint)
            .frame(width: 64, height: 64)
            .background(BlitzUI.mint.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private var setupGuide: some View {
        HStack(alignment: .top, spacing: 20) {
            setupStep(.init(number: 1, title: "Open the app", detail: "Launch BlitzRecorder Camera on your iPhone."))
            setupStep(.init(number: 2, title: "Use the same Wi-Fi", detail: "Keep your iPhone and Mac on one network."))
            setupStep(.init(number: 3, title: "Pair below", detail: "Select your iPhone and enter its six-digit code."))
        }
        .settingsSurface()
    }

    private func setupStep(_ step: SetupStep) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(step.number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 24, height: 24)
                .background(BlitzUI.quietFill, in: .circle)
            Text(step.title)
                .font(.system(size: 12, weight: .medium))
            Text(step.detail)
                .font(.system(size: 11))
                .foregroundStyle(BlitzUI.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var nearbyDevices: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Nearby iPhones")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
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
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Waiting for your iPhone")
                            .font(.system(size: 13, weight: .medium))
                        Text("Keep the iPhone app open. Your device will appear here automatically.")
                            .font(.system(size: 12))
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
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(device.isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
                .frame(width: 36, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                Text(device.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
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
        HStack(spacing: 16) {
            phoneIcon
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.selectedRemoteCameraName ?? "iPhone camera")
                    .font(.system(size: 18, weight: .semibold))
                Text(vm.selectedRemoteCameraDeviceDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .lineLimit(2)
                SettingsStatusBadge(configuration: .init(
                    title: vm.selectedRemoteCameraStatus ?? "Waiting for connection",
                    tone: selectedDevice?.isReady == true ? .ready : .warning
                ))
            }
            Spacer(minLength: 8)
            Button(showsDevicePicker ? "Hide devices" : "Change iPhone") {
                showsDevicePicker.toggle()
            }
            .blitzButton(.secondary)
            .disabled(vm.state != .idle)
        }
        .settingsSurface()
    }

    private var cameraWorkspace: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Camera preview")
                    .font(.system(size: 13, weight: .semibold))
                ZStack {
                    Color.black
                    CameraPreviewRepresentable(view: vm.remoteCameraPreviewSurface)
                        .aspectRatio(vm.remoteCameraPreviewAspectRatio, contentMode: .fit)
                    if !vm.hasRemoteCameraPreviewImage {
                        VStack(spacing: 10) {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 28, weight: .light))
                            Text("Waiting for video")
                                .font(.system(size: 12, weight: .medium))
                            Text("Keep the iPhone app open.")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(BlitzUI.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.85))
                    }
                }
                .frame(height: 310)
                .clipShape(.rect(cornerRadius: 10))
                Text(vm.selectedRemoteCameraReviewStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                RemoteCameraOrientationControl(vm: vm, usesPanelBackground: true)
            }
            .frame(width: 260)

            RemoteCameraControlsPane(vm: vm, showsStatusHeader: false)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .settingsSurface()
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
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: showsDirectConnection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityValue(showsDirectConnection ? "Expanded" : "Collapsed")

            if showsDirectConnection {
                Text("If discovery cannot find your iPhone, enter the address and port shown in its app.")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
                HStack(alignment: .bottom, spacing: 10) {
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
            Text(field == .address ? "iPhone address" : "Port")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BlitzUI.secondaryText)
            TextField(
                field == .address ? "192.168.1.10" : "Port",
                text: field == .address ? $vm.directRemoteCameraHost : $vm.directRemoteCameraPort
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focusedField == field ? BlitzUI.mint.opacity(0.6) : BlitzUI.separator, lineWidth: 1)
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
