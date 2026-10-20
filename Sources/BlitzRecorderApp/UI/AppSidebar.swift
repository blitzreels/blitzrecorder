import SwiftUI

enum AppSidebarDestination: Hashable {
    case recordings
    case shared
    case folder(ProjectFolderScope)
    case editor
    case record
    case settings

    struct State {
        let studioMode: RecorderStudioMode
        let isShowingSettings: Bool
        let navigation: ProjectLibraryNavigationState
    }

    init(_ state: State) {
        if state.isShowingSettings {
            self = .settings
            return
        }
        switch state.studioMode {
        case .record: self = .record
        case .edit: self = .editor
        case .projects:
            if state.navigation.section == .shared {
                self = .shared
            } else if let scope = state.navigation.folderScope {
                self = .folder(scope)
            } else {
                self = .recordings
            }
        }
    }
}

extension RecorderViewModel {
    var sidebarDestination: AppSidebarDestination {
        .init(.init(studioMode: studioMode, isShowingSettings: isShowingSettings, navigation: projectLibraryNavigation))
    }

    func showSidebarDestination(_ destination: AppSidebarDestination) {
        switch destination {
        case .recordings: showLibrary(.init(section: .recordings, folderScope: nil))
        case .shared: showLibrary(.init(section: .shared, folderScope: nil))
        case .folder(let scope):
            showLibrary(.init(section: .recordings, folderScope: scope))
        case .editor: openEditor()
        case .record: showRecorder()
        case .settings: showSettings(nil)
        }
    }

    private struct LibraryScope {
        let section: ProjectLibraryNavigationState.Section
        let folderScope: ProjectFolderScope?
    }

    private func showLibrary(_ scope: LibraryScope) {
        guard canShowProjects else { return }
        projectLibraryNavigation.section = scope.section
        projectLibraryNavigation.folderScope = scope.folderScope
        if studioMode == .projects {
            dismissSettings()
        } else {
            showProjects()
        }
    }

    func startNewRecording() {
        guard state == .idle, countdownRemaining == nil else { return showRecorder() }
        switch sidebarDestination {
        case .folder(let scope):
            recordInFolder(recordTarget(scope))
        case .recordings, .shared:
            folderRecordTarget = nil
            showRecorder()
        case .editor, .record, .settings:
            showRecorder()
        }
    }

    var newRecordingFolder: ProjectFolderScope? {
        guard state == .idle, case .folder(let scope) = sidebarDestination else { return nil }
        return scope
    }

    var canOpenEditorFromSidebar: Bool {
        canOpenEditor && canOpenProjectEditor
    }
}

struct AppSidebar: View {
    @Bindable var vm: RecorderViewModel
    let mcpServer: BlitzRecorderMCPServer

    @State private var dropTargetID: String?

    private var editorTitle: String? {
        guard let title = vm.lastExportedProject?.title else { return nil }
        return ProjectTitlePresentation(.init(title: title, known: vm.folderIndex.known)).title
    }

    var body: some View {
        let selection = vm.sidebarDestination
        VStack(alignment: .leading, spacing: 0) {
            AppSidebarRecordButton(vm: vm)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("Library")
                    row(.init(destination: .recordings, title: "Recordings", symbol: "film.stack",
                              detail: nil, trailing: "\(vm.recentProjects.count)", enabled: vm.canShowProjects), selection)
                    row(.init(destination: .shared, title: "Shared", symbol: "link",
                              detail: nil, trailing: nil, enabled: vm.canShowProjects), selection)
                    if vm.canOpenEditor {
                        row(.init(destination: .editor, title: "Editor", symbol: "scissors",
                                  detail: editorTitle, trailing: nil,
                                  enabled: vm.canOpenEditorFromSidebar), selection)
                    }

                    foldersHeader.padding(.top, 18)
                    ForEach(vm.folderTree, id: \.id) { node in
                        folderRow(node, selection)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            .blitzScrollFade(edges: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                if vm.state == .idle {
                    AppUpdateSidebarCard()
                        .padding(.bottom, 8)
                }
                AppSidebarAgentsRow(configuration: .init(mcpServer: mcpServer) {
                    vm.showSettings(.agents)
                })
                AppSidebarLivePreviewToggle(vm: vm)
                row(.init(destination: .settings, title: "Settings", symbol: "gearshape",
                          detail: nil, trailing: "⌘,", enabled: true), selection)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .padding(.top, MainWindowChrome.toolbarHeight)
        .frame(width: MainWindowChrome.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzMaterialBackground(kind: .sidebar))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App navigation")
    }

    private func sectionHeader(_ title: String) -> some View {
        BlitzUI.sectionLabel(title)
            .padding(.horizontal, AppSidebarRow.inset)
            .padding(.bottom, 6)
    }

    private var foldersHeader: some View {
        HStack(spacing: 4) {
            BlitzUI.sectionLabel("Folders")
            Spacer(minLength: 0)
            Button {
                vm.presentFolderPrompt(.create(parent: nil, moving: []))
            } label: {
                Image(systemName: "plus")
                    .font(BlitzType.symbol(11))
                    .frame(width: 18, height: 18)
            }
            .blitzButton(.quiet)
            .controlSize(.mini)
            .disabled(vm.projectTrash.isWorking)
            .help("New folder")
            .accessibilityLabel("New folder")
        }
        .padding(.leading, AppSidebarRow.inset)
        .padding(.trailing, 4)
        .padding(.bottom, 6)
    }

    private func folderRow(_ node: ProjectFolderTree.Node, _ selection: AppSidebarDestination) -> some View {
        let scope = ProjectFolderScope(path: node.path, module: nil)
        let dropID = "sidebar-folder-\(node.id)"
        let isSelected = if case .folder(let selected) = selection { selected.path.hasPrefix(node.path) } else { false }
        return AppSidebarRow(configuration: .init(
            item: .init(destination: .folder(scope), title: node.path.name,
                        symbol: "folder", detail: nil, trailing: "\(node.allProjects.count)",
                        enabled: vm.canShowProjects),
            isSelected: isSelected,
            isDropTarget: dropTargetID == dropID,
            action: { vm.showSidebarDestination(.folder(scope)) }
        ))
        .projectDropTarget(.init(id: dropID, target: $dropTargetID) { ids in
            vm.dropProjects(.init(ids: ids, destination: vm.folderDestination(node)))
        })
        .contextMenu { ProjectFolderMenu(vm: vm, node: node) }
        .help("Drop recordings here to move them into \(node.path.displayPath)")
    }

    private func row(_ item: AppSidebarRow.Item, _ selection: AppSidebarDestination) -> some View {
        AppSidebarRow(configuration: .init(
            item: item,
            isSelected: item.destination == selection,
            isDropTarget: false,
            action: { vm.showSidebarDestination(item.destination) }
        ))
    }
}

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

struct AppSidebarAgentsRow: View {
    struct Configuration {
        let mcpServer: BlitzRecorderMCPServer
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    private var status: BlitzRecorderMCPServerStatus { configuration.mcpServer.status }

    var body: some View {
        Button(action: configuration.action) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(BlitzType.symbol(14))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 20)
                Text("AI agents")
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.supportingText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                BlitzStatusDot(tone: tone, diameter: 6)
                Text(status.title)
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
            RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous)
                .fill(isHovering ? BlitzUI.quietFill : .clear)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: status)
        .help(help)
        .accessibilityLabel("AI agents")
        .accessibilityValue(status.title)
        .accessibilityHint("Opens Integrations settings")
    }

    private var tone: BlitzStatusTone {
        switch status {
        case .running, .portInUse: .ready
        case .failed: .warning
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

struct AppSidebarLivePreviewToggle: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        Toggle(isOn: Binding(get: { vm.isLivePreviewEnabled }, set: { vm.setLivePreviewEnabled($0) })) {
            HStack(spacing: 10) {
                Image(systemName: vm.isLivePreviewEnabled ? "eye" : "eye.slash")
                    .font(BlitzType.symbol(14))
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(width: 20)
                Text("Live preview")
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.supportingText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .toggleStyle(.blitzSwitch)
        .controlSize(.mini)
        .padding(.horizontal, AppSidebarRow.inset)
        .frame(minHeight: AppSidebarRow.height)
        .disabled(vm.state != .idle)
        .help(vm.state == .idle
              ? "Pause camera, microphone, screen, and audio previews while idle (⌥⌘L). Recording still works."
              : "Change live preview after this recording")
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
        .pointingHandCursor()
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

struct AppSidebarShortcuts: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ZStack {
            shortcut(.init(title: "New Recording", key: "n", modifiers: .command) { vm.startNewRecording() })
            shortcut(.init(title: "Show Recordings", key: "1", modifiers: .command) { vm.showSidebarDestination(.recordings) })
            shortcut(.init(title: "Show Shared", key: "2", modifiers: .command) { vm.showSidebarDestination(.shared) })
            shortcut(.init(title: "Show Editor", key: "3", modifiers: .command) {
                if vm.canOpenEditorFromSidebar { vm.showSidebarDestination(.editor) }
            })
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private struct Shortcut {
        let title: String
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let action: () -> Void
    }

    private func shortcut(_ shortcut: Shortcut) -> some View {
        Button(shortcut.title, action: shortcut.action)
            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

struct AppSidebarToggle: View {
    @Binding var isSidebarHidden: Bool

    var body: some View {
        Button {
            isSidebarHidden.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(BlitzType.symbol(13))
                .frame(width: 18)
                .overlay(alignment: .topTrailing) {
                    if isSidebarHidden { AppUpdateBadge().offset(x: 4, y: -3) }
                }
        }
        .blitzButton(.quiet)
        .controlSize(.small)
        .keyboardShortcut("s", modifiers: [.control, .command])
        .help(isSidebarHidden ? "Show sidebar (⌃⌘S)" : "Hide sidebar (⌃⌘S)")
        .accessibilityLabel(isSidebarHidden ? "Show sidebar" : "Hide sidebar")
    }
}

struct StudioExitButton: View {
    struct Configuration {
        let destination: AppSidebarDestination
        let action: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        Button(action: configuration.action) {
            Label(configuration.destination == .editor ? "Editor" : "Library", systemImage: "chevron.left")
                .font(BlitzType.label)
        }
        .blitzButton(.quiet)
        .controlSize(.small)
        .help(configuration.destination == .editor ? "Back to the editor" : "Back to your recordings")
    }
}
