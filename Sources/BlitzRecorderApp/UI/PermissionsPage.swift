import AppKit
import SwiftUI

struct PermissionsPage: View {
    @Bindable var vm: RecorderViewModel

    private var captureRows: [PermissionStatusRow] {
        vm.permissionStatusRows.filter { $0.source != nil }
    }

    private var needsAccess: Bool {
        captureRows.contains { $0.isActive && $0.level != .granted }
    }

    private var hasEnabledSources: Bool {
        captureRows.contains { $0.isActive }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(.init(
                    title: "Permissions",
                    detail: "Control what BlitzRecorder can capture on this Mac.",
                    systemImage: "lock.shield",
                    status: nil
                ))

                accessSummary

                VStack(spacing: 0) {
                    ForEach(Array(captureRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { SettingsRowDivider() }
                        permissionRow(row)
                    }
                }
                .settingsSection(.init(title: "Capture access", detail: nil, systemImage: "record.circle"))

                if let row = vm.permissionStatusRows.first(where: { $0.source == nil }) {
                    permissionRow(row)
                        .settingsSection(.init(
                            title: "Window controls",
                            detail: nil,
                            systemImage: "macwindow"
                        ))
                }

                Label("macOS controls access to this Mac. Changes apply when you return to BlitzRecorder.", systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .onAppear { vm.refreshPermissionStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vm.refreshPermissionStatus()
        }
    }

    private var accessSummary: some View {
        HStack(spacing: 16) {
            Image(systemName: needsAccess ? "lock.shield" : "checkmark.shield")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(needsAccess ? BlitzUI.warning : BlitzUI.mint)
                .frame(width: 50, height: 50)
                .background(
                    (needsAccess ? BlitzUI.warning : BlitzUI.mint).opacity(0.08),
                    in: .rect(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(!hasEnabledSources ? "No capture sources enabled" : needsAccess ? "Review capture access" : "Your capture access is ready")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BlitzUI.primaryText)
                Text(!hasEnabledSources ? "Enable a source in the recorder to check its access." : needsAccess
                     ? "Some enabled sources need your permission before recording."
                     : "All enabled sources have the permissions they need.")
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                vm.refreshPermissionStatus()
            } label: {
                Label("Recheck", systemImage: "arrow.clockwise")
            }
            .blitzButton(.secondary)
            .help("Refresh permission status")
        }
        .settingsSurface()
    }

    private func permissionRow(_ row: PermissionStatusRow) -> some View {
        HStack(spacing: 12) {
            BlitzSymbol(configuration: .init(name: row.symbol, size: 19))
                .foregroundStyle(BlitzUI.secondaryText)
                .frame(width: 36, height: 36)
                .background(BlitzUI.quietFill, in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(row.title == "System Audio" ? "Mac audio" : row.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BlitzUI.primaryText)
                    if row.isOptional {
                        Text("Optional")
                            .font(.system(size: 10))
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                Text(purpose(row))
                    .font(.system(size: 12))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsStatusBadge(configuration: .init(title: statusTitle(row), tone: statusTone(row)))
                .frame(width: 100, alignment: .trailing)

            Button(row.level == .warning && row.status == "not determined" ? "Allow…" : "Manage…") {
                manage(row)
            }
            .blitzButton(.secondary)
            .accessibilityLabel("Manage \(row.title) permission")
            .help("Open \(row.title.lowercased()) permission controls")
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
    }

    private func purpose(_ row: PermissionStatusRow) -> String {
        if row.level == .blocked { return row.status.capitalized }
        switch row.source {
        case .screen: return "Record a display, window, or selected area."
        case .camera: return vm.isRemoteCameraSelected ? "The paired iPhone provides camera access." : "Include a camera in your recording."
        case .microphone: return "Record your voice from the selected microphone."
        case .systemAudio: return "Capture sound from apps on your Mac."
        case nil: return "Move and resize the window you are recording."
        }
    }

    private func statusTitle(_ row: PermissionStatusRow) -> String {
        switch row.level {
        case .granted: return row.status == "remote iPhone" ? "On iPhone" : "Allowed"
        case .warning: return "Needs access"
        case .blocked: return "Blocked"
        case .inactive: return row.isOptional ? "Not enabled" : "Not in use"
        }
    }

    private func statusTone(_ row: PermissionStatusRow) -> BlitzStatusTone {
        switch row.level {
        case .granted: .ready
        case .warning, .blocked: .warning
        case .inactive: .muted
        }
    }

    private func manage(_ row: PermissionStatusRow) {
        switch row.source {
        case .screen, .systemAudio:
            vm.openScreenRecordingSettings()
        case .camera:
            if vm.isRemoteCameraSelected {
                vm.showSettings(.devices)
            } else if row.status == "not determined" {
                vm.requestCameraAccessFromCover()
            } else {
                vm.openCameraSettings()
            }
        case .microphone:
            if row.status == "not determined" {
                vm.requestMicrophoneAccessFromCover()
            } else {
                vm.openMicrophoneSettings()
            }
        case nil:
            vm.openAccessibilitySettings()
        }
    }
}
