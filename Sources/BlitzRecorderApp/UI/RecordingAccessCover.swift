import AppKit
import BlitzRecorderCore
import SwiftUI

/// Full-window first-run cover that gates the app behind recording permissions.
/// Hides the main UI entirely until the selected sources are granted, instead of
/// floating a card over a live, clickable app.
struct RecordingAccessCover: View {
    @Bindable var vm: RecorderViewModel

    private let accent = BlitzUI.mint

    /// The four capture sources (Accessibility lives in the Access tab, not here).
    private var sourceRows: [PermissionStatusRow] {
        vm.permissionStatusRows.filter { $0.source != nil }
    }

    private var activeRows: [PermissionStatusRow] {
        sourceRows.filter { $0.isActive }
    }

    private var readyCount: Int {
        activeRows.filter(\.isGranted).count
    }

    private var requiredCount: Int {
        activeRows.count
    }

    private var isReady: Bool {
        vm.recordingReadiness.isReady
    }

    private var hasAllowable: Bool {
        sourceRows.contains { coverAction(for: $0) == .allow }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                hero
                    .padding(.bottom, 26)

                permissionCard
                    .frame(maxWidth: 520)
                    .animation(.smooth(duration: 0.35), value: readyCount)
                    .animation(.smooth(duration: 0.35), value: vm.screenAccessAwaitingRestart)

                statusLine
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                footer
                    .frame(maxWidth: 520)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check the instant the user returns from System Settings.
            vm.refreshPermissionStatus()
        }
        .task {
            // Light poll so a grant made while the cover is up reflects without a click.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                vm.refreshPermissionStatus()
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.03, blue: 0.04),
                    Color(red: 0.06, green: 0.06, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.12), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)

            VStack(spacing: 6) {
                Text("Welcome to BlitzRecorder")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Allow a few permissions and you're ready to record.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sourceRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                        .background(.white.opacity(0.06))
                        .padding(.horizontal, 14)
                }
                AccessPermissionRow(
                    row: row,
                    action: coverAction(for: row),
                    accent: accent,
                    onTap: { performAction(for: row) }
                )
            }
        }
        .padding(.vertical, 6)
        .blitzGlassSurface(cornerRadius: 18)
        .shadow(color: .black.opacity(0.34), radius: 28, y: 14)
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if isReady {
                Label("All set — you're ready to record", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(accent)
            } else if requiredCount > 0 {
                Text("\(readyCount) of \(requiredCount) permissions ready")
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("Select a source in BlitzRecorder to begin")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .animation(.smooth(duration: 0.3), value: readyCount)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                vm.startFromCover()
            } label: {
                Label("Start Recording", systemImage: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .blitzProminentGlassButton()
            .tint(accent)
            .disabled(!isReady)
            .opacity(isReady ? 1 : 0.45)
            .pointingHandCursor()

            HStack(spacing: 18) {
                if hasAllowable {
                    Button {
                        vm.allowAllFromCover()
                    } label: {
                        Text("Allow All")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }

                Button {
                    vm.dismissFirstRunOnboarding()
                } label: {
                    Text("Set up later")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private func coverAction(for row: PermissionStatusRow) -> CoverAction {
        guard let source = row.source else { return .inactive }
        if !row.isActive { return .inactive }
        if row.isGranted { return .granted }
        switch source {
        case .screen, .systemAudio:
            return vm.screenAccessAwaitingRestart ? .quitReopen : .allow
        case .camera, .microphone:
            // notDetermined can be resolved with an in-app prompt; denied/restricted needs Settings.
            return row.status == "not determined" ? .allow : .openSettings
        }
    }

    private func performAction(for row: PermissionStatusRow) {
        guard let source = row.source else { return }
        switch coverAction(for: row) {
        case .granted, .inactive:
            break
        case .allow:
            switch source {
            case .screen, .systemAudio: vm.requestScreenAccessFromCover()
            case .camera: vm.requestCameraAccessFromCover()
            case .microphone: vm.requestMicrophoneAccessFromCover()
            }
        case .openSettings:
            switch source {
            case .screen, .systemAudio: vm.openScreenRecordingSettings()
            case .camera: vm.openCameraSettings()
            case .microphone: vm.openMicrophoneSettings()
            }
        case .quitReopen:
            vm.quitAndReopen()
        }
    }
}

private enum CoverAction: Equatable {
    case granted
    case allow
    case openSettings
    case quitReopen
    case inactive
}

private struct AccessPermissionRow: View {
    let row: PermissionStatusRow
    let action: CoverAction
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(action == .inactive ? 0.4 : 0.92))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(action == .inactive ? 0.3 : 0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        guard let source = row.source else { return "" }
        switch action {
        case .inactive: return "Not in current setup"
        case .quitReopen: return "Enabled — restart to finish"
        default: return source.onboardingPurpose
        }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(badgeColor.opacity(0.16))
            Image(systemName: row.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(badgeColor)
        }
        .frame(width: 34, height: 34)
    }

    private var badgeColor: Color {
        switch action {
        case .granted: return accent
        case .allow: return .white.opacity(0.8)
        case .openSettings, .quitReopen: return Color(red: 1.0, green: 0.66, blue: 0.16)
        case .inactive: return .white.opacity(0.3)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch action {
        case .granted:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                Text("Granted")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .inactive:
            EmptyView()
        case .allow:
            actionButton("Allow", icon: "lock.open")
        case .openSettings:
            actionButton("Open Settings", icon: "gearshape")
        case .quitReopen:
            actionButton("Quit & Reopen", icon: "arrow.clockwise")
        }
    }

    private func actionButton(_ title: String, icon: String) -> some View {
        Button(action: onTap) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 30)
        }
        .blitzGlassButton()
        .pointingHandCursor()
    }
}
