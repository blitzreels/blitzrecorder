import AppKit
import SwiftUI

struct AgentsSettingsPage: View {
    private struct Capability: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
    }

    private static let capabilities = [
        Capability(
            id: "projects",
            title: "Find projects",
            detail: "List, search, and filter local BlitzRecorder projects.",
            icon: "rectangle.stack"
        ),
        Capability(
            id: "transcripts",
            title: "Inspect transcripts",
            detail: "Read saved transcripts and project details.",
            icon: "text.quote"
        ),
        Capability(
            id: "export",
            title: "Export MP4 files",
            detail: "Use the default folder or an authorized subfolder for each export job.",
            icon: "square.and.arrow.up"
        ),
        Capability(
            id: "status",
            title: "Track export jobs",
            detail: "Monitor pending projects, failures, and completed output paths.",
            icon: "progress.indicator"
        ),
    ]

    @Bindable var mcpServer: BlitzRecorderMCPServer
    @State private var copiedValue: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Agents",
                    detail: "Connect local AI agents to projects, transcripts, and MP4 exports.",
                    systemImage: "terminal",
                    status: statusTitle
                ))
                .padding(.bottom, 4)

                serverSection
                capabilitiesSection
                connectSection
                securitySection
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(.white)
    }

    private var serverSection: some View {
        VStack(spacing: 0) {
            Toggle(isOn: enabledBinding) {
                SettingsRowLabel(.init(
                    title: "Allow local agents",
                    detail: "Start the MCP server automatically while BlitzRecorder is open."
                ))
            }
            .toggleStyle(.switch)
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 16) {
                SettingsRowLabel(.init(
                    title: "WebMCP workspace",
                    detail: "Review local projects with ChatGPT or Codex in the browser."
                ))

                Spacer(minLength: 16)

                Button("Open workspace") {
                    NSWorkspace.shared.open(BlitzRecorderMCPServer.workspaceURL)
                }
                .blitzGlassButton()
                .pointingHandCursor()
                .disabled(mcpServer.status != .running)
            }
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 16) {
                SettingsRowLabel(.init(
                    title: "Server status",
                    detail: statusDetail
                ))

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 16) {
                SettingsRowLabel(.init(
                    title: "Local endpoint",
                    detail: "Streamable HTTP on this Mac only."
                ))

                Spacer(minLength: 16)

                copyableValue(BlitzRecorderMCPServer.endpointURL.absoluteString)
            }
            .settingsRow()

            SettingsRowDivider()

            HStack(alignment: .center, spacing: 16) {
                SettingsRowLabel(.init(
                    title: "Connection test",
                    detail: connectionTestDetail
                ))

                Spacer(minLength: 16)

                Button(connectionTestButtonTitle) {
                    Task {
                        await mcpServer.testConnection()
                    }
                }
                .blitzGlassButton()
                .pointingHandCursor()
                .disabled(mcpServer.status != .running || isTestingConnection)
            }
            .settingsRow()
        }
        .settingsSection(.init(
            title: "Local agent server",
            detail: "BlitzRecorder must remain open while an agent is connected",
            systemImage: "antenna.radiowaves.left.and.right"
        ))
    }

    private var capabilitiesSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.capabilities.enumerated()), id: \.element.id) { index, capability in
                if index > 0 {
                    SettingsRowDivider()
                }
                HStack(alignment: .top, spacing: 12) {
                    BlitzSymbol(configuration: .init(name: capability.icon, size: 18))
                        .foregroundStyle(BlitzUI.mint)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(capability.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(capability.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsRow()
            }
        }
        .settingsSection(.init(
            title: "Agent capabilities",
            detail: "A narrow local surface for safe project work",
            systemImage: "sparkles.rectangle.stack"
        ))
    }

    private var connectSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Codex")
                    .font(.system(size: 12, weight: .semibold))
                Text("Run once, then start a new Codex task so the tools are discovered.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                copyableCode(BlitzRecorderMCPServer.codexSetupCommand)
            }
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Agent Plugin 1.0")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Link(
                        "Open guide",
                        destination: URL(string: "https://agent-plugins.org/plugin-authors")!
                    )
                    .font(.system(size: 11, weight: .semibold))
                }
                Text("Use this portable mcp.json entry in a compatible agent plugin.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                copyableCode(BlitzRecorderMCPServer.agentPluginConfiguration)
            }
            .settingsRow()
        }
        .settingsSection(.init(
            title: "Connect an agent",
            detail: "Copy one setup command into your local agent",
            systemImage: "link"
        ))
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local access only")
                        .font(.system(size: 12, weight: .semibold))
                    Text(
                        "The server does not accept network connections from other devices. "
                            + "Any process on this Mac can use it while enabled."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(BlitzUI.mint)
            }
            .settingsRow()

            SettingsRowDivider()

            Text(
                "Agent exports create normal project export records. "
                    + "They do not rewrite captured source files or saved edits."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .settingsRow()
        }
        .settingsSection(.init(
            title: "Privacy and control",
            detail: "Local access with normal project export records",
            systemImage: "hand.raised"
        ))
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { mcpServer.isEnabled },
            set: { enabled in
                Task {
                    await mcpServer.setEnabled(enabled)
                }
            }
        )
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
        case .disabled:
            "Turn on local agent access to connect."
        case .stopped:
            "The server is not listening."
        case .starting:
            "Opening the local endpoint."
        case .running:
            "Ready for local agent connections."
        case .failed(let message):
            message
        }
    }

    private var statusColor: Color {
        switch mcpServer.status {
        case .running: BlitzUI.mint
        case .starting: BlitzUI.warning
        case .failed: .red
        case .disabled, .stopped: .secondary
        }
    }

    private var isTestingConnection: Bool {
        mcpServer.connectionTestStatus == .testing
    }

    private var connectionTestButtonTitle: String {
        isTestingConnection ? "Testing…" : "Test connection"
    }

    private var connectionTestDetail: String {
        switch mcpServer.connectionTestStatus {
        case .notRun:
            "Verify the complete local MCP handshake."
        case .testing:
            "Connecting to the local endpoint."
        case .succeeded(let date):
            "Connected at \(date.formatted(date: .omitted, time: .shortened))."
        case .failed(let message):
            message
        }
    }

    private func copyableValue(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            Button(copiedValue == value ? "Copied" : "Copy") {
                copy(value)
            }
            .blitzGlassButton()
        }
    }

    private func copyableCode(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ScrollView(.horizontal) {
                Text(value)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(10)
            }
            .background(.black.opacity(0.28), in: .rect(cornerRadius: 7))

            Button(copiedValue == value ? "Copied" : "Copy") {
                copy(value)
            }
            .blitzGlassButton()
            .padding(.top, 5)
        }
    }

    private func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(value, forType: .string) else { return }
        copiedValue = value
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard copiedValue == value else { return }
            copiedValue = nil
        }
    }
}
