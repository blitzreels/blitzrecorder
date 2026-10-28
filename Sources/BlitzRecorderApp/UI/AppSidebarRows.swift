import SwiftUI

struct AppSidebarRow: View {
    struct Item {
        let destination: AppSidebarDestination
        let title: String
        let symbol: String
        let detail: String?
        let trailing: String?
        let enabled: Bool
    }

    struct Configuration {
        let item: Item
        let isSelected: Bool
        let isDropTarget: Bool
        let action: () -> Void
    }

    static let inset: CGFloat = 10
    static let height: CGFloat = 32

    let configuration: Configuration
    @State private var isHovering = false

    private var item: Item { configuration.item }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
        if configuration.isSelected || configuration.isDropTarget {
            BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius)
        } else {
            shape.fill(isHovering && item.enabled ? BlitzUI.quietFill : .clear)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: configuration.action) {
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(BlitzType.symbol(14))
                        .symbolVariant(configuration.isSelected ? .fill : .none)
                        .foregroundStyle(configuration.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(BlitzType.navigation)
                            .foregroundStyle(configuration.isSelected ? BlitzUI.primaryText : BlitzUI.supportingText)
                            .lineLimit(1)
                        if let detail = item.detail {
                            Text(detail)
                                .font(BlitzType.caption)
                                .foregroundStyle(BlitzUI.secondaryText)
                                .monospacedDigit()
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 4)
                    if let trailing = item.trailing {
                        Text(trailing)
                            .font(BlitzType.caption)
                            .monospacedDigit()
                            .foregroundStyle(BlitzUI.tertiaryText)
                    }
                }
                .padding(.horizontal, Self.inset)
                .frame(minHeight: Self.height)
                .padding(.vertical, item.detail == nil ? 0 : 3)
                .contentShape(.rect)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .disabled(!item.enabled)
            .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
            .accessibilityLabel(item.title)
            .accessibilityValue(item.detail ?? item.trailing ?? "")
        }
        .background { background }
        .opacity(item.enabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }
}

/// Settings, with the AI agents (MCP) status as a dot, so the footer is one row.
struct AppSidebarSettingsRow: View {
    struct Configuration {
        let mcpServer: BlitzRecorderMCPServer
        let isSelected: Bool
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    private var status: BlitzRecorderMCPServerStatus { configuration.mcpServer.status }

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(BlitzType.symbol(14))
                    .symbolVariant(configuration.isSelected ? .fill : .none)
                    .foregroundStyle(configuration.isSelected ? BlitzUI.accent : BlitzUI.secondaryText)
                    .frame(width: 20)
                Text("Settings")
                    .font(BlitzType.navigation)
                    .foregroundStyle(configuration.isSelected ? BlitzUI.primaryText : BlitzUI.supportingText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                BlitzStatusDot(tone: tone, diameter: 6)
                Text("Agents")
                    .font(BlitzType.caption)
                    .foregroundStyle(status.servesAgents ? BlitzUI.secondaryText : BlitzUI.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSidebarRow.inset)
            .frame(minHeight: AppSidebarRow.height)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .background {
            if configuration.isSelected {
                BlitzSelectedBackground(cornerRadius: BlitzUI.controlRadius)
            } else {
                RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                    .fill(isHovering ? BlitzUI.quietFill : .clear)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: status)
        .help("Settings (⌘,). AI agents: \(status.title). \(help)")
        .accessibilityLabel("Settings")
        .accessibilityValue("AI agents \(status.title)")
        .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
    }

    private var tone: BlitzStatusTone {
        switch status {
        case .running: .ready
        case .portInUse, .failed: .warning
        case .disabled, .stopped, .starting: .muted
        }
    }

    private var help: String {
        let handshake = configuration.mcpServer.lastClientHandshake.map {
            " \($0.name) last connected at \($0.date.formatted(date: .omitted, time: .shortened))."
        } ?? ""
        let reach = status.servesAgents
            ? "Claude Code, Codex and other MCP clients can use your recordings."
            : "MCP clients cannot reach BlitzRecorder right now."
        return "\(reach) \(status.detail)\(handshake)"
    }
}

struct AppSidebarRecordButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var isHovering = false

    var body: some View {
        Button(action: vm.startNewRecording) {
            HStack(spacing: 10) {
                glyph.frame(width: 20)
                Text(title)
                    .font(BlitzType.section)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(trailing)
                    .font(BlitzType.captionEmphasis)
                    .opacity(0.75)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
            .background(LinearGradient(colors: [BlitzUI.recordRedHighlight, BlitzUI.recordRed],
                                       startPoint: .top, endPoint: .bottom).opacity(isHovering ? 1 : 0.94),
                        in: .rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
            .overlay { BlitzEdgeHighlight(cornerRadius: BlitzUI.controlRadius).opacity(0.8) }
            .shadow(color: BlitzUI.recordGlow, radius: 6, y: 2)
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(vm.projectTrash.isWorking)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }

    @ViewBuilder
    private var glyph: some View {
        switch vm.state {
        case .idle:
            Circle().fill(.white).frame(width: 11, height: 11)
        case .recording:
            Image(systemName: "circle.fill")
                .font(BlitzType.glyph(11))
                .symbolEffect(.pulse, options: .repeating, isActive: true)
        case .paused:
            Image(systemName: "pause.fill").font(BlitzType.glyph(11))
        case .starting, .finishing:
            ProgressView().controlSize(.small).tint(.white)
        }
    }

    private var title: String {
        switch vm.state {
        case .idle: "Record"
        case .recording, .paused: vm.formattedElapsed
        case .starting: "Starting…"
        case .finishing: "Saving…"
        }
    }

    private var trailing: String {
        switch vm.state {
        case .idle: "⌘N"
        case .recording: "Recording"
        case .paused: "Paused"
        case .starting, .finishing: ""
        }
    }

    private var help: String {
        guard vm.state == .idle else { return "Back to the studio" }
        return vm.newRecordingFolder.map { "Record into \($0.title) (⌘N)" } ?? "Open the studio to record (⌘N)"
    }
}
