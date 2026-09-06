import SwiftUI

struct PermissionsPage: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Access",
                    detail: "Review what BlitzRecorder can use and resolve anything blocking capture.",
                    systemImage: "lock.shield",
                    status: vm.recordingReadiness.isReady ? "Ready" : "Needs attention"
                ))
                .padding(.bottom, 4)

                PermissionSetupCard(vm: vm)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    ForEach(Array(vm.permissionStatusRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider()
                                .background(.white.opacity(0.08))
                        }
                        PermissionStatusRowView(row: row) {
                            handleTap(row)
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
        .onAppear {
            vm.refreshPermissionStatus()
        }
    }

    private func handleTap(_ row: PermissionStatusRow) {
        switch row.source {
        case .screen:
            if row.isActive, !vm.isPersistentScreenCaptureAccessActive {
                vm.openScreenRecordingSettings()
                vm.refreshPermissionStatus(message: "Enable Screen Recording for \(appName) in macOS Settings.")
            } else if row.isActive {
                vm.refreshPermissionStatus(message: "Screen Recording is enabled for \(appName).")
            } else {
                vm.refreshPermissionStatus(message: "\(row.title) is not enabled in the current setup.")
            }
        case .systemAudio:
            if row.isBlocked {
                vm.openScreenRecordingSettings()
                vm.refreshPermissionStatus(message: "Enable Screen Recording for Mac audio, then quit and reopen.")
            } else if row.isActive {
                vm.refreshPermissionStatus(message: "System Audio is enabled for recordings.")
            } else {
                vm.refreshPermissionStatus(message: "\(row.title) is not enabled in the current setup.")
            }
        case .camera, .microphone:
            if row.isActive {
                vm.requestSourcePermissions()
            } else {
                vm.refreshPermissionStatus(message: "\(row.title) is not enabled in the current setup.")
            }
        case nil:
            vm.requestAccessibilityPermission()
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "BlitzRecorder"
    }
}

private struct PermissionSetupCard: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: vm.recordingReadiness.isReady ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(statusDetail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    runPrimaryAction()
                } label: {
                    Label(primaryActionTitle, systemImage: primaryActionSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                }
                .blitzGlassButton()
                .pointingHandCursor()

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 8)
    }

    private var statusTitle: String {
        if showsScreenAccessAction {
            return "Screen Recording is off for \(appName)"
        }
        if vm.recordingReadiness.isReady {
            return "Ready to record"
        }
        return "Recording access needs attention"
    }

    private var statusDetail: String {
        if showsScreenAccessAction {
            return "Enable \(appName) under Screen & System Audio Recording in macOS Settings "
                + "for persistent full capture. Screen selection stays in the recorder."
        }
        return vm.permissionSetupSummary
    }

    private var showsScreenAccessAction: Bool {
        vm.settings.enabledSources.contains(.screen)
            && !vm.isPersistentScreenCaptureAccessActive
    }

    private var primaryActionTitle: String {
        showsScreenAccessAction ? "Open macOS Settings" : vm.primaryPermissionActionTitle
    }

    private var primaryActionSymbol: String {
        showsScreenAccessAction ? "gearshape" : "lock.open"
    }

    private func runPrimaryAction() {
        if showsScreenAccessAction {
            vm.openScreenRecordingSettings()
        } else {
            vm.runPrimaryPermissionAction()
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "BlitzRecorder"
    }

    private var tint: Color {
        vm.recordingReadiness.isReady
            ? BlitzUI.mint
            : BlitzUI.warning
    }
}

struct PermissionStatusRowView: View {
    let row: PermissionStatusRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                BlitzSymbol(configuration: .init(name: row.symbol, size: 20))
                    .foregroundStyle(tint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(row.status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: statusSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .contentShape(Rectangle())
        .pointingHandCursor()
        .help(helpText)
    }

    private var tint: Color {
        switch row.level {
        case .granted:
            return BlitzUI.mint
        case .warning:
            return BlitzUI.warning
        case .blocked:
            return BlitzUI.warning
        case .inactive:
            return .white.opacity(0.34)
        }
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        switch row.level {
        case .granted, .inactive:
            return .clear
        case .warning:
            return Color(red: 1.0, green: 0.66, blue: 0.16).opacity(0.08)
        case .blocked:
            return Color(red: 1.0, green: 0.24, blue: 0.22).opacity(0.10)
        }
    }

    private var statusSymbol: String {
        if row.isOptional, row.level == .inactive {
            return "info.circle.fill"
        }
        switch row.level {
        case .granted:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        case .inactive:
            return "minus.circle.fill"
        }
    }

    private var helpText: String {
        if row.isOptional, row.level == .inactive {
            return "\(row.title) is optional. Click to enable target-window controls."
        }
        switch row.level {
        case .granted:
            return "\(row.title) access is active. Click to recheck."
        case .warning:
            return "\(row.title) needs confirmation. Click to request access."
        case .blocked:
            return "\(row.title) is blocked. Click to open the permission flow."
        case .inactive:
            return "\(row.title) is not enabled in the current setup."
        }
    }
}

@MainActor
func labeledPicker<Value: Hashable, Content: View>(
    _ title: String,
    selection: Binding<Value>,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
        Picker("", selection: selection, content: content)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
