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
            expandedFolderIDs.formUnion(scope.path.ancestorsAndSelf.map(\.id))
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

    var canOpenEditorFromSidebar: Bool {
        canOpenEditor && state == .idle && !projectTrash.isWorking
    }
}

struct AppSidebar: View {
    @Bindable var vm: RecorderViewModel

    @State private var dropTargetID: String?

    private var editorTitle: String? {
        guard let title = vm.lastExportedProject?.title else { return nil }
        return ProjectTitlePresentation(.init(title: title, known: vm.folderIndex.known)).title
    }

    var body: some View {
        let selection = vm.sidebarDestination
        VStack(alignment: .leading, spacing: 0) {
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

                    foldersHeader.padding(.top, 14)
                    ForEach(vm.folderTree.flatMap { visibleNodes($0) }, id: \.id) { entry in
                        folderTreeRow(entry, selection)
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
                row(.init(destination: .record, title: recordingTitle,
                          symbol: vm.state == .idle ? "record.circle" : "record.circle.fill",
                          detail: recordingDetail, trailing: nil,
                          enabled: !vm.projectTrash.isWorking), selection)
                row(.init(destination: .settings, title: "Settings", symbol: "gearshape",
                          detail: nil, trailing: "⌘,", enabled: true), selection)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .padding(.top, MainWindowChrome.toolbarHeight)
        .frame(width: MainWindowChrome.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BlitzUI.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App navigation")
    }

    private func sectionHeader(_ title: String) -> some View {
        BlitzUI.sectionLabel(title)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
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
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.bottom, 4)
    }

    private enum FolderTreeEntry: Identifiable {
        case folder(ProjectFolderTree.Node)
        case module(ProjectFolderTree.Node, ProjectFolderTree.Module)

        var id: String {
            switch self {
            case .folder(let node): node.id
            case .module(let node, let module): "\(node.id)#\(module.id)"
            }
        }
    }

    private func visibleNodes(_ node: ProjectFolderTree.Node) -> [FolderTreeEntry] {
        guard vm.expandedFolderIDs.contains(node.id) else { return [.folder(node)] }
        return [.folder(node)] + node.modules.map { .module(node, $0) } + node.children.flatMap { visibleNodes($0) }
    }

    @ViewBuilder
    private func folderTreeRow(_ entry: FolderTreeEntry, _ selection: AppSidebarDestination) -> some View {
        switch entry {
        case .folder(let node):
            let hasChildren = !node.modules.isEmpty || !node.children.isEmpty
            let dropID = "sidebar-folder-\(node.id)"
            AppSidebarRow(configuration: .init(
                item: .init(destination: .folder(.init(path: node.path, module: nil)), title: node.path.name,
                            symbol: "folder", detail: nil, trailing: "\(node.allProjects.count)",
                            enabled: vm.canShowProjects),
                depth: node.path.segments.count - 1,
                isSelected: selection == .folder(.init(path: node.path, module: nil)),
                isDropTarget: dropTargetID == dropID,
                tint: nil, pulses: false,
                disclosure: hasChildren ? .init(isExpanded: vm.expandedFolderIDs.contains(node.id), toggle: {
                    if vm.expandedFolderIDs.contains(node.id) { vm.expandedFolderIDs.remove(node.id) }
                    else { vm.expandedFolderIDs.insert(node.id) }
                }) : nil,
                action: { vm.showSidebarDestination(.folder(.init(path: node.path, module: nil))) }
            ))
            .projectDropTarget(.init(id: dropID, target: $dropTargetID) { ids in
                vm.dropProjects(.init(ids: ids, destination: vm.folderDestination(node)))
            })
            .contextMenu { ProjectFolderMenu(vm: vm, node: node) }
            .help("Drop recordings here to move them into \(node.path.displayPath)")
        case .module(let node, let module):
            let scope = ProjectFolderScope(path: node.path, module: module.id)
            let dropID = "sidebar-module-\(node.id)-\(module.id)"
            AppSidebarRow(configuration: .init(
                item: .init(destination: .folder(scope), title: "Module \(ProjectLessonCode.number(module.id))",
                            symbol: "rectangle.stack", detail: nil, trailing: "\(module.projects.count)",
                            enabled: vm.canShowProjects),
                depth: node.path.segments.count,
                isSelected: selection == .folder(scope),
                isDropTarget: dropTargetID == dropID,
                tint: module.duplicateLessonIDs.isEmpty ? nil : BlitzUI.warning, pulses: false,
                disclosure: nil,
                action: { vm.showSidebarDestination(.folder(scope)) }
            ))
            .projectDropTarget(.init(id: dropID, target: $dropTargetID) { ids in
                vm.dropProjects(.init(ids: ids, destination: .folder(path: node.path, module: module.id, before: nil)))
            })
            .contextMenu { ProjectModuleMenu(vm: vm, node: node, module: module) }
        }
    }

    private var recordingTitle: String {
        switch vm.state {
        case .idle: "Record"
        case .paused: "Paused"
        case .starting, .recording, .finishing: "Recording"
        }
    }

    private var recordingDetail: String? {
        switch vm.state {
        case .idle: nil
        case .recording: vm.formattedElapsed
        case .paused: vm.formattedElapsed
        case .starting: "Starting…"
        case .finishing: "Saving…"
        }
    }

    private func row(_ item: AppSidebarRow.Item, _ selection: AppSidebarDestination) -> some View {
        AppSidebarRow(configuration: .init(
            item: item,
            depth: 0,
            isSelected: item.destination == selection,
            isDropTarget: false,
            tint: item.destination == .record ? BlitzUI.recordRed : nil,
            pulses: item.destination == .record && vm.state == .recording,
            disclosure: nil,
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

    struct Disclosure {
        let isExpanded: Bool
        let toggle: () -> Void
    }

    struct Configuration {
        let item: Item
        let depth: Int
        let isSelected: Bool
        let isDropTarget: Bool
        let tint: Color?
        let pulses: Bool
        let disclosure: Disclosure?
        let action: () -> Void
    }

    let configuration: Configuration
    @State private var isHovering = false

    private var item: Item { configuration.item }

    private var fill: Color {
        if configuration.isSelected || configuration.isDropTarget { return BlitzUI.selectedFill }
        return isHovering && item.enabled ? BlitzUI.hoverFill : .clear
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: configuration.action) {
                HStack(spacing: 9) {
                    Image(systemName: item.symbol)
                        .font(BlitzType.symbol(13))
                        .symbolVariant(configuration.isSelected ? .fill : .none)
                        .foregroundStyle(configuration.tint ?? (configuration.isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText))
                        .symbolEffect(.pulse, options: .repeating, isActive: configuration.pulses)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(configuration.isSelected ? BlitzType.strong : BlitzType.label)
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
                .padding(.leading, 8 + CGFloat(configuration.depth) * AppSidebarRow.indent)
                .padding(.trailing, configuration.disclosure == nil ? 8 : 2)
                .frame(minHeight: 28)
                .padding(.vertical, item.detail == nil ? 0 : 3)
                .contentShape(.rect)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .disabled(!item.enabled)
            .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
            .accessibilityLabel(item.title)
            .accessibilityValue(item.detail ?? item.trailing ?? "")

            if let disclosure = configuration.disclosure {
                Button(action: disclosure.toggle) {
                    Image(systemName: "chevron.right")
                        .font(BlitzType.symbol(9))
                        .foregroundStyle(BlitzUI.tertiaryText)
                        .rotationEffect(.degrees(disclosure.isExpanded ? 90 : 0))
                        .frame(width: 20, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(BlitzPressButtonStyle())
                .accessibilityLabel("\(disclosure.isExpanded ? "Collapse" : "Expand") \(item.title)")
            }
        }
        .background(fill, in: .rect(cornerRadius: BlitzUI.controlRadius))
        .opacity(item.enabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }

    static let indent: CGFloat = 14
}

struct AppSidebarShortcuts: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        ZStack {
            shortcut(.init(title: "New Recording", key: "n", modifiers: .command) { vm.showSidebarDestination(.record) })
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
