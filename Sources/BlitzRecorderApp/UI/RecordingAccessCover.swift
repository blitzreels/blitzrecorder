import AppKit
import BlitzRecorderCore
import SwiftUI

/// Full-window first-run cover that gates the app behind recording permissions.
/// Hides the main UI entirely until the selected sources are granted, instead of
/// floating a card over a live, clickable app.
struct RecordingAccessCover: View {
    @Bindable var vm: RecorderViewModel

    private let accent = BlitzUI.mint

    private var sourceRows: [PermissionStatusRow] {
        vm.permissionStatusRows.filter { $0.source != nil }
    }

    private var accessibilityRow: PermissionStatusRow? {
        vm.permissionStatusRows.first { $0.source == nil }
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
        Self.canContinue(rows: sourceRows)
    }

    static func canContinue(rows: [PermissionStatusRow]) -> Bool {
        let activeRows = rows.filter(\.isActive)
        return !activeRows.isEmpty && activeRows.allSatisfy(\.isGranted)
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
                    BlitzUI.canvasBackground,
                    BlitzUI.projectLibraryBackground
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
                .clipShape(RoundedRectangle(cornerRadius: BlitzUI.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)

            VStack(spacing: 6) {
                Text("Welcome to BlitzRecorder")
                    .font(BlitzType.largeTitle)
                    .foregroundStyle(.white)
                Text("Allow a few permissions and you're ready to record.")
                    .font(BlitzType.callout)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var permissionCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sourceRows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                        .background(BlitzUI.controlFill)
                        .padding(.horizontal, 14)
                }
                AccessPermissionRow(
                    row: row,
                    action: coverAction(for: row),
                    accent: accent,
                    isRequesting: vm.isRequestingPermissions,
                    onTap: { performAction(for: row) },
                    onOpenSettings: vm.openScreenRecordingSettings
                )
            }
            if let row = accessibilityRow {
                Divider()
                    .background(BlitzUI.controlFill)
                    .padding(.horizontal, 14)
                AccessPermissionRow(
                    row: row,
                    action: coverAction(for: row),
                    accent: accent,
                    isRequesting: vm.isRequestingPermissions,
                    onTap: { performAction(for: row) },
                    onOpenSettings: vm.openScreenRecordingSettings
                )
            }
        }
        .padding(.vertical, 6)
        .blitzGlassSurface(cornerRadius: BlitzUI.surfaceRadius)
        .shadow(color: .black.opacity(0.34), radius: 28, y: 14)
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if isReady {
                Label("Permissions ready — continue to the recorder", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(accent)
            } else if requiredCount > 0 {
                Text("\(readyCount) of \(requiredCount) permissions ready")
                    .foregroundStyle(BlitzUI.secondaryText)
            } else {
                Text("Select a source in BlitzRecorder to begin")
                    .foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .font(BlitzType.strong)
        .animation(.smooth(duration: 0.3), value: readyCount)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                vm.startFromCover()
            } label: {
                Label("Continue to recorder", systemImage: "arrow.right")
                    .font(BlitzType.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .blitzButton(.accent)
            .tint(accent)
            .disabled(!isReady || vm.isRequestingPermissions)
            .opacity(isReady ? 1 : 0.45)
            .pointingHandCursor()

            HStack(spacing: 18) {
                if hasAllowable {
                    Button("Allow selected sources", action: vm.allowAllFromCover)
                        .blitzButton(.quiet)
                        .controlSize(.small)
                        .disabled(vm.isRequestingPermissions)
                }

                Button("Set up later", action: vm.dismissFirstRunOnboarding)
                    .blitzButton(.quiet)
                    .controlSize(.small)
            }
        }
    }

    private func coverAction(for row: PermissionStatusRow) -> CoverAction {
        guard let source = row.source else {
            if row.isGranted { return .granted }
            return vm.coordinator.permissionGate.hasRequestedAccessibilityAccessThisSession
                ? .openSettings : .allow
        }
        if source == .systemAudio && !row.isActive { return .enable }
        if !row.isActive { return .inactive }
        if row.isGranted { return .granted }
        switch source {
        case .screen:
            if vm.screenAccessAwaitingRestart { return .quitReopen }
            return vm.coordinator.permissionGate.hasRequestedScreenCaptureAccessThisSession
                ? .openSettings : .allow
        case .systemAudio:
            if vm.screenAccessAwaitingRestart { return .quitReopen }
            return vm.coordinator.permissionGate.hasRequestedScreenCaptureAccessThisSession
                ? .openSettings : .allow
        case .camera, .microphone:
            // notDetermined can be resolved with an in-app prompt; denied/restricted needs Settings.
            return row.status == "not determined" ? .allow : .openSettings
        }
    }

    private func performAction(for row: PermissionStatusRow) {
        guard let source = row.source else {
            switch coverAction(for: row) {
            case .allow: vm.requestAccessibilityPermission()
            case .openSettings: vm.openAccessibilitySettings()
            default: break
            }
            return
        }
        switch coverAction(for: row) {
        case .granted, .inactive:
            break
        case .enable:
            vm.enableSystemAudioFromCover()
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
    case enable
    case allow
    case openSettings
    case quitReopen
    case inactive
}

private struct AccessPermissionRow: View {
    let row: PermissionStatusRow
    let action: CoverAction
    let accent: Color
    let isRequesting: Bool
    let onTap: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            iconBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(BlitzType.section)
                    .foregroundStyle(action == .inactive ? BlitzUI.tertiaryText : BlitzUI.primaryText)
                Text(subtitle)
                    .font(BlitzType.captionEmphasis)
                    .foregroundStyle(action == .inactive ? BlitzUI.tertiaryText : BlitzUI.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        guard let source = row.source else {
            return row.isGranted ? "Window controls ready" : "Optional — move and resize captured windows"
        }
        switch action {
        case .inactive: return "Not in current setup"
        case .enable: return "Optional — record sound from apps"
        case .quitReopen: return "After enabling in Settings, reopen BlitzRecorder"
        default: return source.onboardingPurpose
        }
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                .fill(badgeColor.opacity(0.16))
            Image(systemName: row.symbol)
                .font(BlitzType.glyph(14))
                .foregroundStyle(badgeColor)
        }
        .frame(width: 34, height: 34)
    }

    private var badgeColor: Color {
        switch action {
        case .granted: return accent
        case .allow, .enable: return BlitzUI.supportingText
        case .openSettings, .quitReopen: return BlitzUI.warning
        case .inactive: return BlitzUI.tertiaryText
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
            .font(BlitzType.strong)
            .foregroundStyle(accent)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .inactive:
            EmptyView()
        case .enable:
            actionButton("Enable", icon: "speaker.wave.2")
        case .allow:
            actionButton("Allow", icon: "lock.open")
        case .openSettings:
            actionButton("Open Settings", icon: "gearshape")
        case .quitReopen:
            HStack(spacing: 6) {
                Button("Settings…", action: onOpenSettings)
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .disabled(isRequesting)
                actionButton("Quit & Reopen", icon: "arrow.clockwise")
            }
        }
    }

    private func actionButton(_ title: String, icon: String) -> some View {
        Button(action: onTap) {
            Label(title, systemImage: icon)
        }
        .blitzButton(.secondary)
        .controlSize(.small)
        .disabled(isRequesting)
        .pointingHandCursor()
    }
}
