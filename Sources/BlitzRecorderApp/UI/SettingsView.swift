import AppKit
import SwiftUI

enum SettingsPane: Int, CaseIterable, Identifiable {
    case recording
    case devices
    case permissions
    case agents
    case about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .recording: return "Recording"
        case .devices: return "iPhone Camera"
        case .permissions: return "Permissions"
        case .agents: return "Integrations"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .recording: return "Files and transcripts"
        case .devices: return "iPhone camera and pairing"
        case .permissions: return "macOS capture permissions"
        case .agents: return "Local MCP connections"
        case .about: return "Version, help, and source code"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "gearshape"
        case .devices: return "iphone.gen3"
        case .permissions: return "lock.shield"
        case .agents: return "terminal"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    struct Configuration {
        let viewModel: RecorderViewModel
        let mcpServer: BlitzRecorderMCPServer
    }

    @Bindable private var vm: RecorderViewModel
    private let mcpServer: BlitzRecorderMCPServer

    init(configuration: Configuration) {
        vm = configuration.viewModel
        mcpServer = configuration.mcpServer
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BlitzToolbarButton(configuration: .init(
                    title: vm.settingsReturnTitle,
                    symbolName: "chevron.left",
                    showsTitle: true,
                    action: vm.dismissSettings
                ))
                .help("Back to \(vm.settingsReturnTitle)")
                .keyboardShortcut(.escape, modifiers: [])

                Rectangle()
                    .fill(BlitzUI.separator)
                    .frame(width: 1, height: 18)

                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()
            }
            .blitzWorkspaceToolbar()

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(BlitzUI.separator)
                    .frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BlitzUI.projectLibraryBackground)
        .tint(BlitzUI.mint)
        .onAppear { NowPlayingController.shared.perform(.pause) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 5) {
                ForEach(SettingsPane.allCases) { pane in
                    sidebarRow(pane)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 24)

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                BlitzStatusDot(tone: .ready, diameter: 6)
                Text("All features are free")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 196)
        .background(Color.black.opacity(0.18))
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        let issueCount = pane == .permissions
            ? vm.recordingReadiness.blockers.count
            : 0
        let isSelected = vm.selectedSettingsPane == pane

        return Button {
            vm.selectedSettingsPane = pane
        } label: {
            HStack(spacing: 11) {
                BlitzSymbol(configuration: .init(name: pane.systemImage, size: 18))
                    .foregroundStyle(isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

                Spacer(minLength: 0)

                if issueCount > 0 {
                    Text("\(issueCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(minWidth: 18, minHeight: 18)
                        .background(BlitzUI.warning, in: .circle)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(pane.subtitle)
        .pointingHandCursor()
    }

    @ViewBuilder
    private var detail: some View {
        switch vm.selectedSettingsPane {
        case .recording:
            RecordingSettingsPage(vm: vm)
        case .devices:
            RemoteCameraPage(vm: vm)
        case .permissions:
            PermissionsPage(vm: vm)
        case .agents:
            AgentsSettingsPage(mcpServer: mcpServer)
        case .about:
            AboutSettingsPage()
        }
    }

}
