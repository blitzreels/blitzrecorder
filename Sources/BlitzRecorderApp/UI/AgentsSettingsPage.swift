import AppKit
import SwiftUI

struct AgentsSettingsPage: View {
    @Bindable var mcpServer: BlitzRecorderMCPServer
    @State private var provider = MCPClientProvider.claudeDesktop
    @State private var clientStatus = MCPClientSetup.Status.missing
    @State private var isConnecting = false
    @State private var setupMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Integrations",
                    detail: "Connect an AI client to recordings, transcripts, video frames, and exports on this Mac.",
                    status: .init(title: statusTitle, isActive: mcpServer.status == .running)
                ))
                serverSection
                connectSection
                SettingsRowLabel(.init(
                    title: "Use it in your next conversation",
                    detail: "Ask your client to list BlitzRecorder recordings. For one video, choose Copy AI context in Recordings and paste it with your request. Copying context does not install a connection."
                ))
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .task(id: provider) {
            setupMessage = nil
            let selected = provider
            let status = await MCPClientSetup.status(.init(provider: selected, home: FileManager.default.homeDirectoryForCurrentUser))
            guard !Task.isCancelled, selected == provider else { return }
            clientStatus = status
        }
    }

    private var serverSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: enabledBinding) {
                SettingsRowLabel(.init(
                    title: "Allow local agents",
                    detail: "Connected clients can read recordings and transcripts, inspect frames, and create exports. Keep BlitzRecorder running while using them."
                ))
            }
            .toggleStyle(.blitzSwitch)
            .settingsRow()
            SettingsRowDivider()
            BlitzAdaptiveRow() {
                SettingsRowLabel(.init(title: "Local endpoint", detail: "Streamable HTTP on this Mac only."))
                copyableValue(BlitzRecorderMCPServer.endpointURL.absoluteString)
            }
            .settingsRow()
            SettingsRowDivider()
            BlitzAdaptiveRow() {
                SettingsRowLabel(.init(title: "Server check", detail: connectionTestDetail))
                Button(isTestingConnection ? "Testing…" : "Test server") {
                    Task { await mcpServer.testConnection() }
                }
                .blitzButton(.secondary)
                .disabled(mcpServer.status != .running || isTestingConnection)
            }
            .settingsRow()
            SettingsRowDivider()
            SettingsRowLabel(.init(
                title: "Client activity",
                detail: mcpServer.lastClientHandshake.map {
                    "\($0.name) connected at \($0.date.formatted(date: .omitted, time: .shortened)). This is the latest handshake, not a permanent connection."
                } ?? "No client handshake observed since this server started. The server check does not count as a client connection."
            ))
            .settingsRow()
        }
        .settingsSection(.init(title: "Local agent server", detail: statusDetail, systemImage: "antenna.radiowaves.left.and.right"))
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BlitzDropdown(configuration: .init(
                title: "AI client", selection: $provider,
                options: MCPClientProvider.allCases.map { .init(value: $0, title: $0.title, detail: nil) },
                menuWidth: 320
            ))
            .disabled(isConnecting)
            .settingsRow()
            SettingsRowDivider()
            VStack(alignment: .leading, spacing: 14) {
                SettingsRowLabel(.init(title: provider.title, detail: provider.detail))
                if provider.canInstallConfiguration {
                    BlitzAdaptiveRow() {
                        Text(clientStatus.detail)
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(isConnecting ? "Connecting…" : "Connect \(provider.title)") {
                            Task { await connectClient() }
                        }
                        .blitzButton(.secondary)
                        .disabled(isConnecting || mcpServer.status != .running || clientStatus == .configured || clientStatus == .conflict)
                    }
                    if let path = provider.relativeConfigurationPath {
                        Text("User configuration: ~/\(path)")
                            .font(BlitzType.footnote)
                            .foregroundStyle(BlitzUI.tertiaryText)
                            .textSelection(.enabled)
                    }
                    DisclosureGroup("Manual setup") {
                        copyableCode(provider.setupCommand ?? provider.configurationText)
                            .padding(.top, 10)
                    }
                    .font(BlitzType.captionEmphasis)
                } else if provider == .claudeDesktop {
                    Button(isConnecting ? "Preparing…" : "Install Claude extension…") {
                        Task { await connectClient() }
                    }
                    .blitzButton(.secondary)
                    .disabled(isConnecting || mcpServer.status != .running)
                    Text("Claude opens an installation prompt. Enable the extension there, then start a new conversation. Keep BlitzRecorder open.")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                } else if provider == .other {
                    copyableCode(provider.configurationText)
                    if let directory = MCPDesktopExtension.resourceDirectory {
                        Text("For stdio clients with Node.js 18 or later:")
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                        copyableCode(stdioConfiguration(directory))
                    }
                }
                if mcpServer.status != .running, provider != .cloud {
                    Text("Turn on Allow local agents and wait for the server to be ready before connecting.")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                if let setupMessage {
                    Text(setupMessage)
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .settingsRow()
        }
        .settingsSection(.init(
            title: "Connect your AI client",
            detail: "Set up each client once. Tools are discovered after it connects; local apps are not registered automatically.",
            systemImage: "link"
        ))
    }

    private func connectClient() async {
        guard !isConnecting else { return }
        isConnecting = true
        setupMessage = nil
        defer { isConnecting = false }
        do {
            if provider == .claudeDesktop {
                let bundle = try await MCPDesktopExtension.createBundle()
                if NSWorkspace.shared.open(bundle) {
                    setupMessage = "Extension installation opened. Complete Claude's prompt to grant access; installation is not yet verified."
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([bundle])
                    setupMessage = "Extension ready in Finder. In Claude, open Settings > Extensions > Advanced settings > Install Extension and select BlitzRecorder.mcpb."
                }
            } else {
                let request = MCPClientSetup.Request(provider: provider, home: FileManager.default.homeDirectoryForCurrentUser)
                try await MCPClientSetup.install(request)
                clientStatus = await MCPClientSetup.status(request)
                setupMessage = "Connection saved. Start a new session in \(provider.title), approve the tools, then ask it to list BlitzRecorder recordings."
            }
        } catch {
            setupMessage = error.localizedDescription
        }
    }

    private func stdioConfiguration(_ directory: URL) -> String {
        let value: [String: Any] = ["mcpServers": ["blitzrecorder": [
            "command": "node", "args": [directory.appendingPathComponent("bridge.cjs").path]
        ]]]
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { mcpServer.isEnabled }, set: { enabled in Task { await mcpServer.setEnabled(enabled) } })
    }

    private var statusTitle: String {
        switch mcpServer.status {
        case .disabled: "Off"
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Running"
        case .failed: "Unavailable"
        }
    }

    private var statusDetail: String {
        switch mcpServer.status {
        case .disabled: "Turn on local agent access to connect."
        case .stopped: "The server is not listening."
        case .starting: "Opening the local endpoint."
        case .running: "Server available. Each AI client still needs its own connection."
        case .failed(let message): message
        }
    }

    private var isTestingConnection: Bool { mcpServer.connectionTestStatus == .testing }

    private var connectionTestDetail: String {
        switch mcpServer.connectionTestStatus {
        case .notRun: "Check the handshake, tool discovery, and a read-only library request. This does not configure your client."
        case .testing: "Checking the handshake, recording tools, and library access…"
        case .succeeded(let result): "Server verified: \(result.toolCount) tools and library access at \(result.date.formatted(date: .omitted, time: .shortened))."
        case .failed(let message): message
        }
    }

    private func copyableValue(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value).font(BlitzType.captionEmphasis.monospaced()).textSelection(.enabled)
            copyButton(value)
        }
    }

    private func copyableCode(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ScrollView(.horizontal) {
                Text(value)
                    .font(BlitzType.footnote.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
            copyButton(value).padding(.top, 5)
        }
    }

    private func copyButton(_ value: String) -> some View {
        BlitzCopyButton(configuration: .init(
            text: value, title: "Copy", accessibilityLabel: "Copy setup", help: "Copy to the clipboard",
            emphasis: .secondary, width: .fit
        ))
    }
}
