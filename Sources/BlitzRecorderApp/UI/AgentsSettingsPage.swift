import AppKit
import SwiftUI

struct AgentsSettingsPage: View {
    @Bindable var mcpServer: BlitzRecorderMCPServer
    @State private var copiedValue: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Integrations",
                    detail: "Connect local AI agents to projects, transcripts, and MP4 exports.",
                    status: .init(title: statusTitle, isActive: mcpServer.status == .running)
                ))
                .padding(.bottom, 4)

                serverSection
                connectSection
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
                    detail: "Let local agents read projects and transcripts and create exports."
                ))
            }
            .toggleStyle(.blitzSwitch)
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
                .blitzButton(.secondary)
                .pointingHandCursor()
                .disabled(mcpServer.status != .running || isTestingConnection)
            }
            .settingsRow()
        }
        .settingsSection(.init(
            title: "Local agent server",
            detail: statusDetail,
            systemImage: "antenna.radiowaves.left.and.right"
        ))
    }

    private var connectSection: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                IntegrationProviderTitle(configuration: .init(title: "Claude Code", imageName: "IntegrationClaude",
                                                              fallbackSymbol: "sparkle"))
                Text("Run once in Terminal, then start a new Claude Code session.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                copyableCode(BlitzRecorderMCPServer.claudeCodeSetupCommand)
            }
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                IntegrationProviderTitle(configuration: .init(title: "Codex", imageName: "IntegrationCodex",
                                                              fallbackSymbol: "chevron.left.forwardslash.chevron.right"))
                Text("Run once, then start a new Codex task so the tools are discovered.")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.secondaryText)
                copyableCode(BlitzRecorderMCPServer.codexSetupCommand)
            }
            .settingsRow()

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IntegrationProviderTitle(configuration: .init(title: "Agent Plugin 1.0", imageName: nil,
                                                                  fallbackSymbol: "puzzlepiece.extension.fill"))
                    Spacer()
                    Link(
                        "Open guide",
                        destination: URL(string: "https://agent-plugins.org/plugin-authors")!
                    )
                    .font(BlitzType.captionEmphasis)
                }
                Text("Use this portable mcp.json entry in a compatible agent plugin.")
                    .font(BlitzType.caption)
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
                .font(BlitzType.captionEmphasis.monospaced())
                .textSelection(.enabled)
            Button(copiedValue == value ? "Copied" : "Copy") {
                copy(value)
            }
            .blitzButton(.secondary)
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
            .background(.black.opacity(0.28), in: .rect(cornerRadius: BlitzUI.controlRadius))

            Button(copiedValue == value ? "Copied" : "Copy") {
                copy(value)
            }
            .blitzButton(.secondary)
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

private struct IntegrationProviderTitle: View {
    struct Configuration {
        let title: String
        let imageName: String?
        let fallbackSymbol: String
    }

    let configuration: Configuration

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let name = configuration.imageName,
                   let url = Bundle.main.url(forResource: name, withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    Image(systemName: configuration.fallbackSymbol)
                        .font(BlitzType.glyph(13))
                        .foregroundStyle(BlitzUI.supportingText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BlitzUI.controlFill, in: .rect(cornerRadius: 6))
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityHidden(true)
            Text(configuration.title).font(BlitzType.strong)
        }
    }
}
