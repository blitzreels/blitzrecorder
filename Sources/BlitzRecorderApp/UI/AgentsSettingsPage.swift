import AppKit
import SwiftUI

struct AgentsSettingsPage: View {
    private struct RowLabelConfiguration {
        let title: String
        let detail: String
    }

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
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                serverSection
                capabilitiesSection
                connectSection
                securitySection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agents")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.primary)

            Text("Connect local AI agents to your projects, transcripts, and MP4 exports.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

            Text("BlitzRecorder must remain open while an agent is connected.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BlitzUI.mint.opacity(0.82))
                .padding(.top, 3)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 10)
    }

    private var serverSection: some View {
        Section("Local agent server") {
            Toggle(isOn: enabledBinding) {
                rowLabel(.init(
                    title: "Allow local agents",
                    detail: "Start the MCP server automatically while BlitzRecorder is open."
                ))
            }
            .toggleStyle(.switch)

            LabeledContent {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusTitle)
                        .font(.system(size: 12, weight: .semibold))
                }
            } label: {
                rowLabel(.init(
                    title: "Server status",
                    detail: statusDetail
                ))
            }

            LabeledContent {
                copyableValue(BlitzRecorderMCPServer.endpointURL.absoluteString)
            } label: {
                rowLabel(.init(
                    title: "Local endpoint",
                    detail: "Streamable HTTP on this Mac only."
                ))
            }

            LabeledContent {
                Button(connectionTestButtonTitle) {
                    Task {
                        await mcpServer.testConnection()
                    }
                }
                .disabled(mcpServer.status != .running || isTestingConnection)
            } label: {
                rowLabel(.init(
                    title: "Connection test",
                    detail: connectionTestDetail
                ))
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("What agents can do") {
            ForEach(Self.capabilities) { capability in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: capability.icon)
                        .font(.system(size: 13, weight: .semibold))
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
                .padding(.vertical, 2)
            }
        }
    }

    private var connectSection: some View {
        Section("Connect an agent") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Codex")
                    .font(.system(size: 12, weight: .semibold))
                Text("Run once, then start a new Codex task so the tools are discovered.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                copyableCode(BlitzRecorderMCPServer.codexSetupCommand)
            }
            .padding(.vertical, 3)

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
            .padding(.vertical, 3)
        }
    }

    private var securitySection: some View {
        Section("Privacy and control") {
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

            Text(
                "Agent exports create normal project export records. "
                    + "They do not rewrite captured source files or saved edits."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
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

    private func rowLabel(_ configuration: RowLabelConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(configuration.title)
                .font(.system(size: 12, weight: .semibold))
            Text(configuration.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
