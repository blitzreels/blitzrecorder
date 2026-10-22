import AppKit
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
                    if vm.selectedRemoteCameraConnectionState == .connected {
                        cameraWorkspace
                    } else {
                        connectionGuide
                    }
                } else if let device = vm.remoteCameraDeviceSummaries.first {
                    readyDevice(device)
                } else {
                    setupSummary
                }

                directConnection
            }
            .settingsPageContent()
            .animation(.easeOut(duration: 0.15), value: vm.remoteCameraDeviceSummaries)
            .animation(.easeOut(duration: 0.15), value: vm.selectedRemoteCameraConnectionState)
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .onAppear { vm.startRemoteCameraDiscovery() }
    }

    private var setupSummary: some View {
        VStack(alignment: .leading, spacing: 18) {
            BlitzAdaptiveRow(.init(minimumContentWidth: 320)) {
                HStack(spacing: 18) {
                    companionIcon(size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A better camera. Right beside you.")
                            .font(BlitzType.title)
                        Text("Open BlitzRecorder Camera on your iPhone, on the same Wi‑Fi. It shows up here with a Connect button.")
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Link(destination: BlitzRecorderProductIdentity.companionInstallURL) {
                    Label("Get iPhone app", systemImage: BlitzSymbols.openLink)
                }
                .blitzButton(.secondary)
                .help("Open \(BlitzRecorderProductIdentity.companionDisplayName)")
            }
            SettingsRowDivider()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking for iPhones nearby")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 8)
                Button("Search again", systemImage: "arrow.clockwise") {
                    vm.startRemoteCameraDiscovery()
                }
                .blitzButton(.quiet)
                .disabled(vm.state != .idle)
            }
            if let continuity = vm.selectedContinuityCamera {
                Text("\(continuity.name) is in use through Continuity Camera. Connecting it here switches to "
                     + "BlitzRecorder Camera, which records in higher quality.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .settingsSurface()
    }

    /// An iPhone with the app open: the page is one Connect button, not setup instructions.
    private func readyDevice(_ device: RemoteCameraDeviceSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            BlitzAdaptiveRow(.init(minimumContentWidth: 320)) {
                HStack(spacing: 18) {
                    companionIcon(size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(device.name) is ready")
                            .font(BlitzType.title)
                        Text(device.isTrusted
                             ? "Paired before. Use it as your camera."
                             : "BlitzRecorder Camera is open on it. Click Connect, then tap Connect on the iPhone.")
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let continuity = vm.selectedContinuityCamera {
                            Text("Replaces \(continuity.name) through Continuity Camera.")
                                .font(BlitzType.caption)
                                .foregroundStyle(BlitzUI.tertiaryText)
                        }
                    }
                }
                Button(device.isTrusted ? "Use iPhone" : "Connect", systemImage: "iphone.gen3") {
                    vm.setCamera(device.cameraID)
                }
                .blitzButton(.accent)
                .controlSize(.large)
                .disabled(vm.state != .idle)
                .keyboardShortcut(.defaultAction)
            }
            let others = Array(vm.remoteCameraDeviceSummaries.dropFirst())
            if !others.isEmpty {
                SettingsRowDivider()
                ForEach(others, id: \.id) { other in
                    deviceRow(other)
                }
            }
        }
        .settingsSurface()
    }

    private func companionIcon(size: CGFloat) -> some View {
        BlitzAppIcon(image: Self.companionAppIcon.map(Image.init(nsImage:)), size: size)
    }

    private static let companionAppIcon = Bundle.main.url(forResource: "CompanionAppIcon", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

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
                Button(device.isTrusted ? "Use camera" : "Connect") {
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
                companionIcon(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.selectedRemoteCameraName ?? "iPhone camera")
                        .font(BlitzType.title)
                    if vm.selectedRemoteCameraDeviceDescription != vm.selectedRemoteCameraName {
                        Text(vm.selectedRemoteCameraDeviceDescription)
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(2)
                    }
                    SettingsStatusBadge(configuration: .init(
                        title: vm.selectedRemoteCameraStatus ?? "Waiting for connection",
                        tone: selectedDevice?.isReady == true
                            && vm.selectedRemoteCameraTelemetry?.previewHealth?.isStale != true ? .ready : .warning
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

    /// Until the iPhone is connected, the page asks for the one thing that is missing instead of an empty preview.
    private var connectionGuide: some View {
        let isAsking = vm.selectedRemoteCameraConnectionState == .pairing && vm.selectedRemoteCameraAbsence == nil
        let name = vm.selectedRemoteCameraName ?? "your iPhone"
        let absence = vm.selectedRemoteCameraAbsence ?? .notFound
        // The device card above already shows the app icon and the short status.
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isAsking ? "Tap Connect on \(name)" : absence.title(deviceName: name))
                    .font(BlitzType.title)
                Text(isAsking
                     ? "BlitzRecorder Camera is asking on the iPhone. You only do this once; after that it connects by itself."
                     : absence.instruction)
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !isAsking, let lastSeen = absence.lastSeen {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.tertiaryText)
                    }
                }
                // Searching cannot wake a sleeping iPhone, so that case offers no button.
                if !isAsking, !absence.isAsleep {
                    HStack(spacing: 8) {
                        if absence == .neverConnected {
                            Link(destination: BlitzRecorderProductIdentity.companionInstallURL) {
                                Label("Get iPhone app", systemImage: BlitzSymbols.openLink)
                            }
                            .blitzButton(.secondary)
                        }
                        Button("Search again", systemImage: "arrow.clockwise") {
                            vm.startRemoteCameraDiscovery()
                        }
                        .blitzButton(.quiet)
                        .disabled(vm.state != .idle)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .settingsSurface()
        .animation(.easeOut(duration: 0.15), value: isAsking)
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
                    .background(.black)
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
            .accessibilityValue(showsDirectConnection ? "Expanded" : "Collapsed")

            if showsDirectConnection {
                Text("If discovery cannot find your iPhone, enter the address and port shown in its app.")
                    .font(BlitzType.body)
                    .foregroundStyle(BlitzUI.secondaryText)
                BlitzAdaptiveRow(.init(minimumContentWidth: 200)) {
                    connectionField(.address)
                    connectionField(.port)
                        .frame(width: 90)
                    VStack(alignment: .leading, spacing: 6) {
                        BlitzUI.sectionLabel(" ")
                            .accessibilityHidden(true)
                        Button {
                            vm.connectDirectRemoteCamera()
                        } label: {
                            Label("Connect", systemImage: "arrow.right")
                                .frame(height: 36)
                        }
                        .blitzButton(.secondary)
                        .disabled(!canConnect)
                    }
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
