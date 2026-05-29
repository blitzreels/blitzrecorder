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
                    Label("Camera", systemImage: "camera")
                }
                .tag(CameraCompanionTab.recordings)

            CameraMediaLibraryView(store: store)
                .tabItem {
                    Label("Clips", systemImage: "film.stack")
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

            VStack(alignment: .leading, spacing: 0) {
                topBar
                Spacer(minLength: 16)
                statusPanel
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
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
                    Color(uiColor: .systemGray6),
                    Color(uiColor: .systemGray5)
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
                .black.opacity(store.isLiveCameraPreviewEnabled ? 0.56 : 0.08),
                .black.opacity(store.isLiveCameraPreviewEnabled ? 0.12 : 0.02),
                .black.opacity(store.isLiveCameraPreviewEnabled ? 0.72 : 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera")
                    .font(.title2.weight(.semibold))
                Text(topStatusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let headerStatus {
                CameraStatusIndicator(status: headerStatus)
            }
        }
        .foregroundStyle(primaryForegroundStyle)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusSummary

            if !store.hasCompletedPairing {
                pairingControls
                macAppLink
            }

            if !store.pendingRecordings.isEmpty {
                pendingRecordings
            }

            if store.recordingPhase == .recording || store.recordingPhase == .stopping {
                Button(role: .destructive) {
                    store.stopFromPhone()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.recordingPhase != .recording)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionGlassPanel(cornerRadius: 24)
    }

    private var pairingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: signalIcon)
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.connectionIssueTitle)
                        .font(.headline.weight(.semibold))
                    Text(store.connectionIssueRecovery)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "qrcode")
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pairing code")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(store.pairingCode)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                Button {
                    store.retryConnection()
                } label: {
                    Label(detectButtonTitle, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showsDiagnostics = true
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStatusText)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if let secondaryStatusText {
                    Text(secondaryStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var detectButtonTitle: String {
        store.canRetryConnection ? "Try Again" : "Detect Mac"
    }

    private var macAppLink: some View {
        Link(destination: BlitzRecorderProductIdentity.macInstallURL) {
            HStack(spacing: 12) {
                ProductIconImage(
                    image: Bundle.main.blitzRecorderMacIcon,
                    fallbackSystemImage: "macbook",
                    size: 44,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(BlitzRecorderProductIdentity.macDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("Mac app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(BlitzRecorderProductIdentity.macDisplayName)")
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
                "\(store.pendingRecordingCount) saved clip\(store.pendingRecordingCount == 1 ? "" : "s")",
                systemImage: "tray.and.arrow.up"
            )
                .font(.subheadline.weight(.semibold))
        }
        .tint(.primary)
    }

    private var headerStatus: CameraHeaderStatus? {
        guard store.hasCompletedPairing else {
            return nil
        }
        switch store.recordingPhase {
        case .recording:
            return CameraHeaderStatus(text: "Recording", icon: "record.circle", color: .red)
        case .transferring:
            return CameraHeaderStatus(text: "Saving", icon: "arrow.up.doc", color: .primary)
        case .pendingImport:
            return CameraHeaderStatus(text: "Saved", icon: "tray.and.arrow.up", color: .primary)
        default:
            return nil
        }
    }

    private var topStatusText: String {
        if store.hasCompletedPairing {
            return store.pairedMacName ?? "Connected"
        }

        switch store.connectionState {
        case .discovering:
            return "Waiting for Mac"
        case .pairing:
            return "Connecting"
        case .degraded:
            return "Weak connection"
        case .unavailable:
            return "Unavailable"
        case .disconnected:
            return "Disconnected"
        case .connected:
            return "Connected"
        }
    }

    private var primaryStatusText: String {
        if !store.hasCompletedPairing {
            switch store.connectionState {
            case .degraded:
                return "Connection is weak"
            case .unavailable:
                return "Can’t find the Mac"
            case .disconnected:
                return "Disconnected"
            default:
                return "Ready to connect"
            }
        }

        switch store.recordingPhase {
        case .preparing:
            return "Preparing"
        case .recording:
            return store.elapsedLabel
        case .stopping:
            return "Stopping"
        case .transferring:
            return "Saving"
        case .pendingImport:
            return "Saved"
        case .failed:
            return "Needs attention"
        case .idle:
            return store.isLiveCameraPreviewEnabled ? "Live" : "Ready"
        }
    }

    private var secondaryStatusText: String? {
        if !store.hasCompletedPairing {
            switch store.connectionState {
            case .degraded, .unavailable, .disconnected:
                return "Open BlitzRecorder on your Mac."
            default:
                return "Open BlitzRecorder on your Mac."
            }
        }

        switch store.recordingPhase {
        case .recording:
            return "Recording for BlitzRecorder"
        case .preparing, .stopping:
            return nil
        case .transferring:
            return "Saving the clip"
        case .pendingImport:
            return "Ready on this iPhone"
        case .failed:
            return store.statusMessage
        case .idle:
            return nil
        }
    }

    private var statusIcon: String {
        if !store.hasCompletedPairing {
            switch store.connectionState {
            case .pairing: return "link.badge.plus"
            case .degraded: return "wifi.exclamationmark"
            case .unavailable: return "exclamationmark.triangle"
            case .disconnected: return "link.badge.plus"
            default: return "macbook.and.iphone"
            }
        }

        switch store.recordingPhase {
        case .recording: return "record.circle"
        case .transferring: return "arrow.up.doc"
        case .pendingImport: return "tray.and.arrow.up"
        default: return "link.circle.fill"
        }
    }

    private var signalIcon: String {
        switch store.connectionState {
        case .discovering:
            return "dot.radiowaves.left.and.right"
        case .pairing:
            return "link.badge.plus"
        case .connected:
            return "link.circle.fill"
        case .degraded:
            return "wifi.exclamationmark"
        case .disconnected, .unavailable:
            return "wifi.slash"
        }
    }

	private var primaryForegroundStyle: Color {
		store.isLiveCameraPreviewEnabled ? .white : .primary
	}
}

private struct ConnectionDiagnosticsView: View {
	@Bindable var store: CameraCompanionStore
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section("Connection") {
					DiagnosticRow(title: "Status", value: store.connectionTitle)
					DiagnosticRow(title: "Message", value: store.statusMessage)
					DiagnosticRow(title: "Listening Port", value: store.listeningPortLabel)
					DiagnosticRow(title: "Pairing Code", value: store.pairingCode)
				}

				Section("Device") {
					DiagnosticRow(title: "Preview", value: store.previewHealthLabel)
					DiagnosticRow(title: "Storage Free", value: store.freeStorageLabel)
					DiagnosticRow(title: "Thermal", value: store.thermalStateLabel)
					DiagnosticRow(title: "Pending Clips", value: "\(store.pendingRecordingCount)")
				}

				Section {
					Button {
						store.retryConnection()
					} label: {
						Label("Detect Mac Again", systemImage: "arrow.clockwise")
					}
				}
			}
			.navigationTitle("Connection")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done") {
						dismiss()
					}
				}
			}
		}
	}
}

private struct DiagnosticRow: View {
	let title: String
	let value: String

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.body)
				.textSelection(.enabled)
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
                Text(recording.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: retry) {
                Image(systemName: "arrow.clockwise.icloud")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .disabled(recording.takeID == nil)
            .accessibilityLabel("Retry")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Delete")
        }
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

private struct ProductIconImage: View {
    let image: UIImage?
    let fallbackSystemImage: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct CameraMediaLibraryView: View {
    @Bindable var store: CameraCompanionStore
    @State private var confirmsDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LibraryMetricRow(title: "Clips", value: "\(store.pendingRecordingCount)", icon: "film.stack")
                    LibraryMetricRow(title: "Storage", value: store.freeStorageLabel, icon: "internaldrive")
                }

                Section {
                    if store.pendingRecordings.isEmpty {
                        ContentUnavailableView(
                            "No clips",
                            systemImage: "film.stack",
                            description: Text("Clips from this iPhone appear here.")
                        )
                    } else {
                        Button(role: .destructive) {
                            confirmsDeleteAll = true
                        } label: {
                            Label("Delete All Clips", systemImage: "trash")
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
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .tint(.blue)
                                    .disabled(recording.takeID == nil)
                                }
                                .contextMenu {
                                    Button {
                                        store.retryPendingImport(recording)
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .disabled(recording.takeID == nil)

                                    Button(role: .destructive) {
                                        store.deletePendingRecording(recording)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .accessibilityAction(named: "Retry") {
                                    store.retryPendingImport(recording)
                                }
                                .accessibilityAction(named: "Delete") {
                                    store.deletePendingRecording(recording)
                                }
                        }
                    }
                } header: {
                    Text("Local clips")
                }
            }
            .navigationTitle("Clips")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDeleteAll = true
                    } label: {
                        Label("Delete All Clips", systemImage: "trash")
                    }
                    .disabled(store.pendingRecordings.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete all clips?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All Clips", role: .destructive) {
                    store.deleteAllPendingRecordings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes \(store.pendingRecordingCount) clip\(store.pendingRecordingCount == 1 ? "" : "s") from this iPhone.")
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

private extension Bundle {
    var blitzRecorderMacIcon: UIImage? {
        guard let url = url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
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
}
