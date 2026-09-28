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
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()
            }
            .blitzWindowToolbar(showsUpdate: true)

            BlitzSegmentedPicker(configuration: .init(
                title: "Settings section", options: SettingsPane.allCases,
                selection: $vm.selectedSettingsPane, label: { $0.title }, symbolName: { $0.systemImage }
            ))
            .controlSize(.regular)
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BlitzUI.projectLibraryBackground)
        .tint(BlitzUI.mint)
        .onAppear { NowPlayingController.shared.perform(.pause) }
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
