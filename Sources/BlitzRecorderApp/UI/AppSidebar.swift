import SwiftUI

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
                    row(.init(destination: .recordings, title: "Recordings", symbol: BlitzSymbols.library,
                              detail: nil, trailing: "\(vm.recentProjects.count)", enabled: vm.canShowProjects), selection)
                    row(.init(destination: .shared, title: "Shared", symbol: BlitzSymbols.share,
                              detail: nil, trailing: nil, enabled: vm.canShowProjects), selection)
                    if vm.canOpenEditor {
                        row(.init(destination: .editor, title: "Editor", symbol: BlitzSymbols.edit,
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
                        symbol: BlitzSymbols.folder, detail: nil, trailing: "\(node.allProjects.count)",
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
