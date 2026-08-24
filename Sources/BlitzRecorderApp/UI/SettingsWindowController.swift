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

    var subtitle: String {
        switch self {
        case .recording: return "Quality, files, and transcripts"
        case .devices: return "iPhone camera and pairing"
        case .permissions: return "macOS capture permissions"
        case .agents: return "Local MCP connections"
        case .account: return "License and open source"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "record.circle"
        case .devices: return "iphone.gen3"
        case .permissions: return "lock.shield"
        case .agents: return "terminal"
        case .account: return "person.crop.circle"
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
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.setContentSize(SettingsRootView.contentSize)
        window.minSize = NSSize(width: 940, height: 640)
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
    static let contentSize = NSSize(width: 1_120, height: 760)

    @Bindable var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(BlitzUI.separator)
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BlitzUI.projectLibraryBackground)
        .tint(BlitzUI.mint)
        .frame(minWidth: 940, minHeight: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BlitzUI.mint.opacity(0.13))
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(BlitzUI.mint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BlitzRecorder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.90))
                    Text("Settings")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 48)
            .padding(.bottom, 16)

            VStack(spacing: 5) {
                ForEach(SettingsPane.allCases) { pane in
                    sidebarRow(pane)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                BlitzStatusDot(tone: .ready, diameter: 6)
                Text("Changes save automatically")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 238)
        .background(Color.black.opacity(0.18))
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        let issueCount = pane == .permissions
            ? navigation.viewModel.recordingReadiness.blockers.count
            : 0
        let isSelected = navigation.selectedPane == pane

        return Button {
            navigation.selectedPane = pane
        } label: {
            HStack(spacing: 11) {
                BlitzIconTile(
                    symbolName: pane.systemImage,
                    isSelected: isSelected,
                    size: 31
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.62))
                    Text(pane.subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(isSelected ? 0.46 : 0.28))
                        .lineLimit(1)
                }

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
            .frame(height: 52)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.white.opacity(0.085) : Color.clear,
            in: .rect(cornerRadius: 10)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(BlitzUI.mint)
                    .frame(width: 3, height: 24)
                    .offset(x: -1)
            }
        }
        .pointingHandCursor()
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selectedPane {
        case .recording:
            RecordingSettingsPage(vm: navigation.viewModel)
        case .devices:
            RemoteCameraPage(vm: navigation.viewModel)
        case .permissions:
            PermissionsPage(vm: navigation.viewModel)
        case .agents:
            AgentsSettingsPage(mcpServer: navigation.mcpServer)
        case .account:
            BlitzReelsCreatorPage(access: navigation.viewModel.accessController)
        }
    }

}
