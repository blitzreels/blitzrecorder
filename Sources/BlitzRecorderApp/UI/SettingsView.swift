import AppKit
import SwiftUI

enum SettingsPane: Int, CaseIterable, Identifiable {
    case recording
    case speakers
    case devices
    case permissions
    case accounts
    case agents
    case about
#if DEBUG
    case uiKit
#endif

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .speakers: return "Speakers"
        case .recording: return "Recording"
        case .devices: return "iPhone Camera"
        case .permissions: return "Permissions"
        case .accounts: return "Accounts"
        case .agents: return "Integrations"
        case .about: return "About"
#if DEBUG
        case .uiKit: return "UI Kit"
#endif
        }
    }

    var subtitle: String {
        switch self {
        case .speakers: return "Saved voices and samples"
        case .recording: return "Files and transcripts"
        case .devices: return "iPhone camera and pairing"
        case .permissions: return "macOS capture permissions"
        case .accounts: return "BlitzRecorder and BlitzReels"
        case .agents: return "Connect AI agents over MCP"
        case .about: return "Version, help, and source code"
#if DEBUG
        case .uiKit: return "Dev builds only"
#endif
        }
    }

    var systemImage: String {
        switch self {
        case .speakers: return "person.wave.2"
        case .recording: return "gearshape"
        case .devices: return "iphone.gen3"
        case .permissions: return "lock.shield"
        case .accounts: return "person.crop.circle"
        case .agents: return "terminal"
        case .about: return "info.circle"
#if DEBUG
        case .uiKit: return "swatchpalette"
#endif
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
                    .font(BlitzType.section)

                Spacer()
            }
            .blitzWindowToolbar()

            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(BlitzUI.separator).frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BlitzUI.projectLibraryBackground)
        .tint(BlitzUI.mint)
        .onAppear { NowPlayingController.shared.perform(.pause) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                let isSelected = vm.selectedSettingsPane == pane
                Button { vm.selectedSettingsPane = pane } label: {
                    HStack(spacing: 10) {
                        Image(systemName: pane.systemImage)
                            .symbolVariant(.fill)
                            .font(BlitzType.glyph(12))
                            .foregroundStyle(isSelected ? .black.opacity(0.85) : BlitzUI.supportingText)
                            .frame(width: 24, height: 24)
                            .background(isSelected ? BlitzUI.mint : BlitzUI.controlFill,
                                        in: .rect(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pane.title)
                                .font(BlitzType.label)
                                .foregroundStyle(BlitzUI.primaryText)
                            Text(pane.subtitle)
                                .font(BlitzType.caption)
                                .foregroundStyle(BlitzUI.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(BlitzSelectionButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 240)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    @ViewBuilder
    private var detail: some View {
        switch vm.selectedSettingsPane {
        case .recording:
            RecordingSettingsPage(vm: vm)
        case .speakers:
            SpeakersSettingsPage(projects: vm.recentProjects, openRecording: { project in
                vm.projectLibraryNavigation.section = .recordings
                vm.projectLibraryNavigation.searchText = ""
                vm.projectLibraryNavigation.filters = ProjectLibraryFilters()
                vm.projectLibraryNavigation.selectedProjectIDs = [project.id]
                vm.showProjects()
            })
        case .devices:
            RemoteCameraPage(vm: vm)
        case .permissions:
            PermissionsPage(vm: vm)
        case .accounts:
            AccountsSettingsPage(vm: vm)
        case .agents:
            AgentsSettingsPage(mcpServer: mcpServer)
        case .about:
            AboutSettingsPage()
#if DEBUG
        case .uiKit:
            BlitzUIKitView()
#endif
        }
    }

}
