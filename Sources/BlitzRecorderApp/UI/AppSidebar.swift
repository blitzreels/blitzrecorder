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
                .padding(.bottom, 12)

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
                        .foregroundStyle(configuration.isSelected ? BlitzUI.primaryText : BlitzUI.secondaryText)
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
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .padding(.vertical, item.detail == nil ? 0 : 3)
                .contentShape(.rect)
            }
            .buttonStyle(BlitzPressButtonStyle())
            .disabled(!item.enabled)
            .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
            .accessibilityLabel(item.title)
            .accessibilityValue(item.detail ?? item.trailing ?? "")
        }
        .background(fill, in: .rect(cornerRadius: BlitzUI.controlRadius))
        .opacity(item.enabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }
}

struct AppSidebarRecordButton: View {
    @Bindable var vm: RecorderViewModel
    @State private var isHovering = false

    var body: some View {
        Button(action: vm.startNewRecording) {
            HStack(spacing: 10) {
                glyph.frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(BlitzType.section)
                        .monospacedDigit()
                    if let detail {
                        Text(detail)
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.supportingText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                if vm.state == .idle {
                    Text("⌘N")
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.secondaryText)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(BlitzUI.recordRed.opacity(isHovering ? 1 : 0.9),
                        in: .rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: BlitzUI.controlRadius, style: .continuous))
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(vm.projectTrash.isWorking)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .help(vm.state == .idle ? "Open the studio to record (⌘N)" : "Back to the studio")
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
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

    private var detail: String? {
        switch vm.state {
        case .idle: vm.newRecordingFolder.map { "Into \($0.title)" }
        case .recording: "Recording"
        case .paused: "Paused"
        case .starting, .finishing: nil
        }
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
