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

enum CompanionTheme {
    static let accent = Color(red: 0.09, green: 1.0, blue: 0.65)
    static let warning = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let canvasTop = Color(red: 0.025, green: 0.026, blue: 0.034)
    static let canvasBottom = Color(red: 0.075, green: 0.075, blue: 0.095)
    static let panel = Color.white.opacity(0.075)
    static let panelStrong = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.12)
    static let faintText = Color.white.opacity(0.56)
    static let secondaryText = Color.white.opacity(0.70)
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
        .tint(CompanionTheme.accent)
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
        // Content lives in the safe area; the camera surface fills behind it via
        // .background (which ignores safe area internally). Keeping the surface
        // out of the content's ZStack preserves the top/bottom safe-area insets
        // so controls never collide with the status bar or home indicator.
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Spacer(minLength: 18)
            statusPanel
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                background
                readabilityOverlay
            }
        }
        .toolbarBackground(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var background: some View {
        if store.isLiveCameraPreviewEnabled {
            CameraPreview(session: store.camera.session)
                .ignoresSafeArea()
        } else if let preview = store.screenshotPreviewImage {
            // Flexible fill + clip so the image fills the screen edge to edge
            // without proposing an oversized layout that would push the control
            // VStack out of the top safe area (matches the gradient's sizing).
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    CompanionTheme.canvasTop,
                    CompanionTheme.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .overlay {
                CompanionStudioGrid()
            }
        }
    }

    private var readabilityOverlay: some View {
        let onCamera = store.isCameraSurfaceVisible
        return LinearGradient(
            colors: [
                .black.opacity(onCamera ? 0.58 : 0.10),
                .black.opacity(onCamera ? 0.18 : 0.02),
                .black.opacity(onCamera ? 0.78 : 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ProductIconImage(
                image: Bundle.main.blitzRecorderCameraIcon,
                fallbackSystemImage: "camera.fill",
                size: 42,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("BlitzRecorder Camera")
                    .font(.headline.weight(.bold))
                Text(topStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CompanionTheme.faintText)
            }

            Spacer(minLength: 12)

            if let headerStatus {
                CameraStatusIndicator(status: headerStatus)
            } else {
                CameraStatusIndicator(
                    status: CameraHeaderStatus(
                        text: store.hasCompletedPairing ? "Ready" : "Pairing",
                        icon: store.hasCompletedPairing ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right",
                        color: store.hasCompletedPairing ? CompanionTheme.accent : CompanionTheme.warning
                    )
                )
            }
        }
        .foregroundStyle(.white)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !store.hasCompletedPairing {
                pairingGuide
            } else {
                statusSummary

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
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(.red)
                    .disabled(store.recordingPhase != .recording)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionGlassPanel(cornerRadius: 24)
    }

    private var pairingGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(pairingTitle)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Text("Follow these steps in order.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CompanionTheme.faintText)
            }

            VStack(alignment: .leading, spacing: 16) {
                CompanionStepRow(
                    number: 1,
                    title: "Open this Mac app",
                    detail: "BlitzRecorder on your Mac.",
                    systemImage: "macbook",
                    appIcon: Bundle.main.blitzRecorderMacIcon
                )

                CompanionStepRow(
                    number: 2,
                    title: "Choose this iPhone",
                    detail: "Pick it as the camera.",
                    systemImage: "iphone"
                )

                HStack(alignment: .top, spacing: 12) {
                    CompanionStepNumber(value: 3)

                    VStack(alignment: .leading, spacing: 5) {
                        CompanionStepTitle(title: "Enter this code", systemImage: "qrcode")

                        Text(store.pairingCode)
                            .font(.system(size: 40, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityLabel("Pairing code \(store.pairingCode)")

                        Text("Type it in the Mac app.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CompanionTheme.faintText)
                    }
                }
            }

            VStack(spacing: 10) {
                Button {
                    store.retryConnection()
                } label: {
                    Label(detectButtonTitle, systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(CompanionTheme.accent)

                Button {
                    showsDiagnostics = true
                } label: {
                    Text("Help / Details")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CompanionTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            if store.recordingPhase == .failed {
                CompanionIssueMark()
            } else {
                CompanionSymbolTile(
                    systemImage: statusIcon,
                    accent: store.recordingPhase == .recording ? .red : CompanionTheme.accent
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(primaryStatusText)
                    .font(.system(size: store.recordingPhase == .recording ? 30 : 20, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if let secondaryStatusText {
                    Text(secondaryStatusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CompanionTheme.faintText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if store.hasCompletedPairing && store.recordingPhase != .failed {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(store.transferProgressLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CompanionTheme.secondaryText)
                        .lineLimit(1)
                    Text(store.thermalStateLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CompanionTheme.faintText)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var detectButtonTitle: String {
        store.canRetryConnection ? "Try Again" : "Find Mac"
    }

    private var pairingTitle: String {
        switch store.connectionState {
        case .degraded:
            return "Connection is weak"
        case .unavailable:
            return "Can’t find the Mac"
        case .disconnected:
            return "Not connected"
        default:
            return "Connect to your Mac"
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
                "\(store.pendingRecordingCount) saved clip\(store.pendingRecordingCount == 1 ? "" : "s")",
                systemImage: "tray.and.arrow.up"
            )
                .font(.subheadline.weight(.semibold))
        }
        .tint(.white)
        .foregroundStyle(.white)
    }

    private var headerStatus: CameraHeaderStatus? {
        guard store.hasCompletedPairing else {
            return nil
        }
        switch store.recordingPhase {
        case .recording:
            return CameraHeaderStatus(text: "Recording", icon: "record.circle", color: .red)
        case .transferring:
            return CameraHeaderStatus(text: "Sending", icon: "arrow.up.doc", color: CompanionTheme.accent)
        case .pendingImport:
            return CameraHeaderStatus(text: "Ready to send", icon: "tray.and.arrow.up", color: CompanionTheme.accent)
        case .failed:
            return CameraHeaderStatus(text: "Check", icon: "exclamationmark.triangle.fill", color: CompanionTheme.warning)
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
            return "Not available"
        case .disconnected:
            return "Not connected"
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
                return "Not connected"
            default:
                return "Ready to connect"
            }
        }

        switch store.recordingPhase {
        case .preparing:
            return "Getting ready"
        case .recording:
            return store.elapsedLabel
        case .stopping:
            return "Stopping"
        case .transferring:
            return "Sending"
        case .pendingImport:
            return "Ready to send"
        case .failed:
            return "Needs help"
        case .idle:
            return store.isCameraSurfaceVisible ? "Live" : "Ready"
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
            return "Recording for your Mac"
        case .preparing, .stopping:
            return nil
        case .transferring:
            return "Sending clip to Mac"
        case .pendingImport:
            return "Saved on this iPhone"
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
        case .failed: return "exclamationmark.triangle.fill"
        default: return "link.circle.fill"
        }
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
					DiagnosticRow(title: "Port", value: store.listeningPortLabel)
					DiagnosticRow(title: "Pairing Code", value: store.pairingCode)
				}

				Section("Device") {
					DiagnosticRow(title: "Live view", value: store.previewHealthLabel)
					DiagnosticRow(title: "Free space", value: store.freeStorageLabel)
					DiagnosticRow(title: "Phone temp", value: store.thermalStateLabel)
					DiagnosticRow(title: "Saved clips", value: "\(store.pendingRecordingCount)")
				}

					Section {
						Button {
							store.retryConnection()
						} label: {
							Label("Find Mac Again", systemImage: "arrow.clockwise")
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
                    .foregroundStyle(.white)
                Text(recording.fileName)
                    .font(.caption)
                    .foregroundStyle(CompanionTheme.faintText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: retry) {
                Image(systemName: "arrow.clockwise.icloud")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .tint(CompanionTheme.accent)
            .disabled(recording.takeID == nil)
            .accessibilityLabel("Retry")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Delete")
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
            .font(.caption2.weight(.heavy))
            .lineLimit(1)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(status.color.opacity(0.14), in: .capsule)
            .overlay {
                Capsule()
                    .stroke(status.color.opacity(0.30), lineWidth: 1)
            }
            .accessibilityLabel(status.text)
    }
}

private struct CompanionStepRow: View {
    let number: Int
    let title: String
    let detail: String
    let systemImage: String
    var appIcon: UIImage? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanionStepNumber(value: number)

            VStack(alignment: .leading, spacing: 4) {
                CompanionStepTitle(title: title, systemImage: systemImage, appIcon: appIcon)

                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CompanionTheme.faintText)
            }
        }
    }
}

private struct CompanionStepTitle: View {
    let title: String
    let systemImage: String
    var appIcon: UIImage? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let appIcon {
                ProductIconImage(
                    image: appIcon,
                    fallbackSystemImage: systemImage,
                    size: 26,
                    cornerRadius: 6
                )
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CompanionTheme.accent)
                    .frame(width: 26, height: 22, alignment: .center)
            }

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}

private struct CompanionStepNumber: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.footnote.weight(.heavy))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(CompanionTheme.accent, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct CompanionSymbolTile: View {
    let systemImage: String
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.14))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.38), lineWidth: 1)
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

private struct CompanionIssueMark: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CompanionTheme.warning.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(CompanionTheme.warning)
                        .frame(width: 4)
                        .padding(.vertical, 9)
                        .padding(.leading, 8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(CompanionTheme.warning.opacity(0.38), lineWidth: 1)
                }

            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(CompanionTheme.warning, in: Circle())
                .offset(x: -7, y: 7)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }
}

struct CompanionStudioGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 34
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 1)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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
                    .fill(CompanionTheme.panelStrong)
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CompanionTheme.secondaryText)
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
            ZStack {
                LinearGradient(
                    colors: [CompanionTheme.canvasTop, CompanionTheme.canvasBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                CompanionStudioGrid()

                List {
                    Section {
                        BlitzRecorderMacInstallCard()
                            .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        LibraryMetricRow(title: "Clips", value: "\(store.pendingRecordingCount)", icon: "film.stack")
                        LibraryMetricRow(title: "Free space", value: store.freeStorageLabel, icon: "internaldrive")
                    }

                    Section {
                        if store.pendingRecordings.isEmpty {
                            ContentUnavailableView(
                                "No clips",
                                systemImage: "film.stack",
                                description: Text("Clips from this iPhone appear here.")
                            )
                            .foregroundStyle(.white)
                            .listRowBackground(Color.clear)
                        } else {
                            Button(role: .destructive) {
                                confirmsDeleteAll = true
                            } label: {
                                Label("Delete All", systemImage: "trash")
                            }
                            .listRowBackground(CompanionTheme.panel)

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
                                .listRowBackground(CompanionTheme.panel)
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
                                        Label("Send Again", systemImage: "arrow.clockwise")
                                    }
                                    .tint(CompanionTheme.accent)
                                    .disabled(recording.takeID == nil)
                                }
                                .contextMenu {
                                    Button {
                                        store.retryPendingImport(recording)
                                    } label: {
                                        Label("Send Again", systemImage: "arrow.clockwise")
                                    }
                                    .disabled(recording.takeID == nil)

                                    Button(role: .destructive) {
                                        store.deletePendingRecording(recording)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .accessibilityAction(named: "Send Again") {
                                    store.retryPendingImport(recording)
                                }
                                .accessibilityAction(named: "Delete") {
                                    store.deletePendingRecording(recording)
                                }
                            }
                        }
                    } header: {
                        Text("Clips on this iPhone")
                            .foregroundStyle(CompanionTheme.faintText)
                    }
                }
                .foregroundStyle(.white)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Clips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDeleteAll = true
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .disabled(store.pendingRecordings.isEmpty)
                }
            }
            .confirmationDialog(
                "Delete all clips?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    store.deleteAllPendingRecordings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes \(store.pendingRecordingCount) clip\(store.pendingRecordingCount == 1 ? "" : "s") from this iPhone.")
            }
        }
        .tint(CompanionTheme.accent)
    }
}

private struct BlitzRecorderMacInstallCard: View {
    private let destination = BlitzRecorderProductIdentity.macInstallURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image("BlitzRecorderCameraIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("BlitzRecorder")

                Text("BlitzRecorder")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CompanionTheme.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Need the Mac app?")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text("Install BlitzRecorder on your Mac to pair this iPhone and record.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CompanionTheme.faintText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Link(destination: destination) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.right")
                        .font(.body.weight(.bold))
                        .frame(width: 22, height: 22)

                    Text("Open blitzrecorder.com")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(CompanionTheme.accent)
            .accessibilityLabel("Open BlitzRecorder website")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .companionGlassPanel(cornerRadius: 18)
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
                .foregroundStyle(.white)
        } label: {
            Label(title, systemImage: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CompanionTheme.secondaryText)
        }
        .listRowBackground(CompanionTheme.panel)
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
                    .foregroundStyle(.white)
                Text(recording.fileName)
                    .font(.caption)
                    .foregroundStyle(CompanionTheme.faintText)
                    .lineLimit(1)
                Text(recording.byteCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CompanionTheme.secondaryText)
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
    var blitzRecorderCameraIcon: UIImage? {
        UIImage(named: "BlitzRecorderCameraIcon")
    }

    var blitzRecorderMacIcon: UIImage? {
        guard let url = url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

extension View {
    func companionGlassPanel(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        self
            .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(interactive ? 0.18 : 0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.36), radius: 24, y: 14)
    }
}
