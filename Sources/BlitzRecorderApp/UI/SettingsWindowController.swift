import AppKit
import Observation
import SwiftUI

enum SettingsPane: Int, CaseIterable, Identifiable {
    case recording
    case devices
    case permissions
    case agents
    case account

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .recording: return "Recording"
        case .devices: return "Devices"
        case .permissions: return "Access"
        case .agents: return "Agents"
        case .account: return "Account"
        }
    }

}

@MainActor
@Observable
private final class SettingsNavigation {
    let viewModel: RecorderViewModel
    let mcpServer: BlitzRecorderMCPServer
    var selectedPane: SettingsPane = .recording

    struct Configuration {
        let viewModel: RecorderViewModel
        let mcpServer: BlitzRecorderMCPServer
    }

    init(_ configuration: Configuration) {
        viewModel = configuration.viewModel
        mcpServer = configuration.mcpServer
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let navigation: SettingsNavigation

    struct Configuration {
        let viewModel: RecorderViewModel
        let mcpServer: BlitzRecorderMCPServer
    }

    init(_ configuration: Configuration) {
        navigation = SettingsNavigation(.init(
            viewModel: configuration.viewModel,
            mcpServer: configuration.mcpServer
        ))
        let rootView = SettingsRootView(navigation: navigation)
            .preferredColorScheme(.dark)
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(SettingsRootView.contentSize)
        window.minSize = NSSize(width: 840, height: 600)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ pane: SettingsPane) {
        navigation.selectedPane = pane
    }
}

private struct SettingsRootView: View {
    static let contentSize = NSSize(width: 1_020, height: 720)

    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: selectedPaneBinding) {
                Section("Settings") {
                    ForEach(SettingsPane.allCases) { pane in
                        sidebarRow(pane)
                            .tag(pane)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 178, ideal: 196, max: 220)
            .safeAreaInset(edge: .bottom) {
                Text("Changes save automatically")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        let issueCount = pane == .permissions
            ? navigation.viewModel.recordingReadiness.blockers.count
            : 0

        return HStack(spacing: 8) {
            Text(pane.title)
                .font(.system(size: 12, weight: .medium))

            Spacer(minLength: 0)

            if issueCount > 0 {
                Text("\(issueCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(minWidth: 17, minHeight: 17)
                    .background(BlitzUI.warning, in: .circle)
            }
        }
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selectedPane {
        case .recording:
            RecordingSettingsPage(vm: navigation.viewModel)
        case .devices:
            RemoteCameraPage(vm: navigation.viewModel)
        case .permissions:
            ScrollView {
                PermissionsPage(vm: navigation.viewModel)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        case .agents:
            AgentsSettingsPage(mcpServer: navigation.mcpServer)
        case .account:
            BlitzReelsCreatorPage(access: navigation.viewModel.accessController)
        }
    }

    private var selectedPaneBinding: Binding<SettingsPane?> {
        Binding(
            get: { navigation.selectedPane },
            set: { selectedPane in
                if let selectedPane {
                    navigation.selectedPane = selectedPane
                }
            }
        )
    }
}
