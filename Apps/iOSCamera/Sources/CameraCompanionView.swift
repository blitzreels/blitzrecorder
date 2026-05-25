import BlitzRecorderCore
import AVFoundation
import SwiftUI
import UIKit

enum CameraCompanionTab: Hashable {
    case recordings
    case library

    init?(url: URL) {
        guard url.scheme == RemoteCameraConstants.companionURLScheme else {
            return nil
        }

        switch url.host?.lowercased() {
        case "library":
            self = .library
        default:
            self = .recordings
        }
    }
}

struct CameraCompanionView: View {
    @Bindable var store: CameraCompanionStore
    @Binding var selectedTab: CameraCompanionTab
    @State private var showsDiagnostics = false

    var body: some View {
        TabView(selection: $selectedTab) {
            recordingsTab
                .tabItem {
                    Label("Recordings", systemImage: "record.circle")
                }
                .tag(CameraCompanionTab.recordings)

            CameraMediaLibraryView(store: store)
                .tabItem {
                    Label("Library", systemImage: "film.stack")
                }
                .tag(CameraCompanionTab.library)
        }
        .tint(.blue)
        .sheet(isPresented: $showsDiagnostics) {
            ConnectionDiagnosticsView(store: store)
        }
        .onChange(of: store.recordingPhase) { _, phase in
            switch phase {
            case .preparing, .recording, .stopping:
                selectedTab = .recordings
            case .idle, .transferring, .pendingImport, .failed:
                break
            }
        }
    }

    private var recordingsTab: some View {
        ZStack {
            background
            readabilityOverlay

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                bottomSurface
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var background: some View {
        if store.isLiveCameraPreviewEnabled {
            CameraPreview(session: store.camera.session)
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemIndigo).opacity(0.72),
                    Color(uiColor: .systemTeal).opacity(0.56),
                    Color(uiColor: .systemGreen).opacity(0.64)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var readabilityOverlay: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.76),
                .black.opacity(0.18),
                .black.opacity(0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BlitzRecorder Camera")
                    .font(.headline.weight(.semibold))
                Text(store.connectionTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 12)

            if let headerStatus {
                CameraStatusIndicator(status: headerStatus)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var bottomSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                bottomSurfaceContent
            }
        } else {
            bottomSurfaceContent
        }
    }

    private var bottomSurfaceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsConnectionRecovery {
                connectionRecovery
                Divider().overlay(.white.opacity(0.18))
            }

            if !store.hasCompletedPairing {
                pairingSection
            } else {
                cameraSection
            }

            Divider().overlay(.white.opacity(0.18))
            deviceFacts
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionGlassPanel(cornerRadius: 24)
        .foregroundStyle(.white)
    }

    private var connectionRecovery: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.connectionIssueTitle)
                        .font(.headline.weight(.semibold))
                    Text(store.connectionIssueRecovery)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: recoveryIcon)
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
            }

            HStack(spacing: 10) {
                Button {
                    store.retryConnection()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .companionButtonStyle(prominent: true)

                Button {
                    showsDiagnostics = true
                } label: {
                    Label("Investigate", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .companionButtonStyle()
            }
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.statusMessage)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text("Open BlitzRecorder on the Mac, choose this iPhone, then enter the code.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "qrcode")
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing code")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.64))
                    Text(store.pairingCode)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Label(pairingStateText, systemImage: pairingStateIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            cameraStatusSummary

            if !store.pendingRecordings.isEmpty {
                pendingRecordings
            }

            if store.recordingPhase == .recording || store.recordingPhase == .stopping {
                Button(role: .destructive) {
                    store.stopFromPhone()
                } label: {
                    Label("Stop iPhone Recording", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.recordingPhase != .recording)
            }
        }
    }

    private var cameraStatusSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.statusMessage)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text("Mac controlled. Thermal \(store.thermalStateLabel).")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private var pendingRecordings: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.pendingRecordings.prefix(3)) { recording in
                    PendingRecordingRow(
                        recording: recording,
                        retry: { store.retryPendingImport(recording) },
                        delete: { store.deletePendingRecording(recording) }
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            Label(
                "\(store.pendingRecordingCount) pending import\(store.pendingRecordingCount == 1 ? "" : "s") - \(store.pendingRecordingsByteCountLabel)",
                systemImage: "tray.and.arrow.up"
            )
                .font(.subheadline.weight(.semibold))
        }
        .tint(.white)
    }

    private var deviceFacts: some View {
        VStack(spacing: 8) {
            fact("Pairing", store.pairingCode, icon: "qrcode")
            fact("Port", store.listeningPortLabel, icon: "network")
            fact("Transfer", store.transferProgressLabel, icon: "arrow.up.doc")
            fact("Preview", store.previewHealthLabel, icon: "waveform.path.ecg")
            fact("Storage", store.freeStorageLabel, icon: "internaldrive")
        }
    }

    private func fact(_ title: String, _ value: String, icon: String) -> some View {
        LabeledContent {
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } label: {
            Label(title, systemImage: icon)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white.opacity(0.78))
    }

    private var showsConnectionRecovery: Bool {
        switch store.connectionState {
        case .degraded, .disconnected, .unavailable:
            return true
        case .discovering, .pairing, .connected:
            return false
        }
    }

    private var headerStatus: CameraHeaderStatus? {
        guard store.hasCompletedPairing else {
            return nil
        }
        switch store.recordingPhase {
        case .recording:
            return CameraHeaderStatus(text: "Recording", icon: "record.circle", color: .red)
        case .transferring:
            return CameraHeaderStatus(text: "Transferring", icon: "arrow.up.doc", color: .white)
        case .pendingImport:
            return CameraHeaderStatus(text: "Pending import", icon: "tray.and.arrow.up", color: .white)
        default:
            return nil
        }
    }

    private var statusIcon: String {
        if !store.hasCompletedPairing {
            switch store.connectionState {
            case .pairing: return "link.badge.plus"
            case .degraded: return "wifi.exclamationmark"
            case .unavailable: return "exclamationmark.triangle"
            default: return "qrcode"
            }
        }

        switch store.recordingPhase {
        case .recording: return "record.circle"
        case .transferring: return "arrow.up.doc"
        case .pendingImport: return "tray.and.arrow.up"
        default: return "link.circle.fill"
        }
    }

    private var recoveryIcon: String {
        switch store.connectionState {
        case .degraded: return "wifi.exclamationmark"
        case .disconnected: return "link.badge.plus"
        case .unavailable: return "exclamationmark.triangle"
        default: return "questionmark.circle"
        }
    }

    private var pairingStateText: String {
        switch store.connectionState {
        case .discovering:
            return "Waiting for the Mac to connect"
        case .pairing:
            return "Mac found. Enter the code on the Mac"
        case .degraded:
            return "Network connection waiting"
        case .unavailable:
            return "Pairing unavailable"
        case .disconnected:
            return "Mac disconnected. Try again from BlitzRecorder"
        case .connected:
            return "Paired"
        }
    }

    private var pairingStateIcon: String {
        switch store.connectionState {
        case .discovering:
            return "macbook.and.iphone"
        case .pairing:
            return "keyboard"
        case .degraded:
            return "wifi.exclamationmark"
        case .unavailable:
            return "exclamationmark.triangle"
        case .disconnected:
            return "link.badge.plus"
        case .connected:
            return "link.circle.fill"
        }
    }
}

private struct PendingRecordingRow: View {
    let recording: CameraPendingRecording
    let retry: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RecordingThumbnailView(url: recording.url)
                .frame(width: 54, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.createdAtLabel)
                    .font(.footnote.weight(.semibold))
                Text("\(recording.byteCountLabel) - \(recording.fileName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: retry) {
                Image(systemName: "arrow.clockwise.icloud")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(recording.takeID == nil)
            .accessibilityLabel("Retry import")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Delete import")
        }
        .foregroundStyle(.white)
    }
}

private struct CameraHeaderStatus {
    let text: String
    let icon: String
    let color: Color
}

private struct CameraStatusIndicator: View {
    let status: CameraHeaderStatus

    var body: some View {
        Label(status.text, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(status.color)
            .accessibilityLabel(status.text)
    }
}

private struct CameraMediaLibraryView: View {
    @Bindable var store: CameraCompanionStore
    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LibraryMetricRow(title: "Stored clips", value: "\(store.pendingRecordingCount)", icon: "film.stack")
                    LibraryMetricRow(title: "Used by clips", value: store.pendingRecordingsByteCountLabel, icon: "internaldrive")
                    LibraryMetricRow(title: "Free storage", value: store.freeStorageLabel, icon: "externaldrive")
                }

                Section("Import cleanup") {
                    Toggle(isOn: $store.keepsRecordingsAfterMacImport) {
                        Label("Keep originals after Mac import", systemImage: "externaldrive.badge.checkmark")
                    }
                }

                Section {
                    if store.pendingRecordings.isEmpty {
                        ContentUnavailableView(
                            "No stored recordings",
                            systemImage: "film.stack",
                            description: Text("Imported clips are removed after the Mac confirms the transfer.")
                        )
                    } else {
                        Button(role: .destructive) {
                            confirmsDeleteAll = true
                        } label: {
                            Label("Delete All Recordings", systemImage: "trash")
                        }

                        ForEach(store.pendingRecordings) { recording in
                            NavigationLink {
                                CameraRecordingPlaybackView(
                                    recording: recording,
                                    retryImport: {
                                        store.retryPendingImport(recording)
                                    },
                                    delete: {
                                        store.deletePendingRecording(recording)
                                    }
                                )
                            } label: {
                                RecordingLibraryRow(recording: recording)
                            }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.deletePendingRecording(recording)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        store.retryPendingImport(recording)
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise.icloud")
                                    }
                                    .tint(.blue)
                                    .disabled(recording.takeID == nil)
                                }
                                .contextMenu {
                                    Button {
                                        store.retryPendingImport(recording)
                                    } label: {
                                        Label("Retry Import", systemImage: "arrow.clockwise.icloud")
                                    }
                                    .disabled(recording.takeID == nil)

                                    Button(role: .destructive) {
                                        store.deletePendingRecording(recording)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .accessibilityAction(named: "Retry import") {
                                    store.retryPendingImport(recording)
                                }
                                .accessibilityAction(named: "Delete") {
                                    store.deletePendingRecording(recording)
                                }
                        }
                    }
                } header: {
                    Text("Local iPhone recordings")
                }
            }
            .navigationTitle("Media Library")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDeleteAll = true
                    } label: {
                        Label("Delete All Recordings", systemImage: "trash")
                    }
                    .disabled(store.pendingRecordings.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete all local iPhone recordings?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All Recordings", role: .destructive) {
                    store.deleteAllPendingRecordings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes \(store.pendingRecordingCount) stored clip\(store.pendingRecordingCount == 1 ? "" : "s") from this iPhone app.")
            }
        }
    }
}

private struct LibraryMetricRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.body.weight(.semibold))
        } label: {
            Label(title, systemImage: icon)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct RecordingLibraryRow: View {
    let recording: CameraPendingRecording

    var body: some View {
        HStack(spacing: 12) {
            RecordingThumbnailView(url: recording.url)
                .frame(width: 78, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.createdAtLabel)
                    .font(.headline)
                Text(recording.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(recording.byteCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct RecordingThumbnailView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                Image(systemName: didFail ? "video.slash" : "video.fill")
                    .font(.title3.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fill)
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            didFail = false
            image = await RecordingThumbnailGenerator.thumbnail(for: url)
            didFail = image == nil
        }
    }
}

private enum RecordingThumbnailGenerator {
    static func thumbnail(for url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)

            guard let result = try? await generator.image(at: .zero) else {
                return nil
            }
            return UIImage(cgImage: result.image)
        }.value
    }
}

private struct ConnectionDiagnosticsView: View {
    let store: CameraCompanionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Current state") {
                    diagnostic("Status", store.connectionTitle)
                    diagnostic("Message", store.statusMessage)
                    diagnostic("Listening port", store.listeningPortLabel)
                    diagnostic("Pairing code", store.pairingCode)
                    diagnostic("Preview", store.camera.isPreviewRunning ? "Running" : "Not running")
                    diagnostic("Pending imports", "\(store.pendingRecordingCount)")
                    diagnostic("Storage free", store.freeStorageLabel)
                    diagnostic("Thermal", store.thermalStateLabel)
                }

                Section("What to check") {
                    Label("Allow Local Network access for BlitzRecorder Camera in iOS Settings.", systemImage: "network")
                    Label("Keep the Mac and iPhone on the same Wi-Fi or trusted network.", systemImage: "wifi")
                    Label("Open BlitzRecorder on the Mac, then select this iPhone again.", systemImage: "macbook.and.iphone")
                    Label("If Bonjour is blocked, use the shown port while pairing from the Mac.", systemImage: "number")
                }

                Section {
                    Button {
                        store.retryConnection()
                        dismiss()
                    } label: {
                        Label("Retry Discovery", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func diagnostic(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }
}

private extension View {
    @ViewBuilder
    func companionGlassPanel(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func companionButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
