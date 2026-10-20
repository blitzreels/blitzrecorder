import AppKit
import SwiftUI

extension ProjectLibraryView {
    var projectSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(BlitzType.glyph(11))
                        .foregroundStyle(BlitzUI.secondaryText)

                    TextField("Search titles and spoken words", text: $vm.projectLibraryNavigation.searchText)
                        .textFieldStyle(.plain)
                        .font(BlitzType.body)
                        .focused($isSearchFocused)
                        .prefersDefaultFocus(false, in: libraryFocus)

                    if isSearchingTranscripts {
                        ProgressView().controlSize(.mini).accessibilityLabel("Searching transcripts")
                    } else if !vm.projectLibraryNavigation.searchText.isEmpty {
                        Button {
                            vm.projectLibraryNavigation.searchText = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(BlitzUI.secondaryText)
                                .frame(width: 22, height: 26)
                        }
                        .buttonStyle(BlitzPressButtonStyle())
                        .accessibilityLabel("Clear project search")
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .blitzFieldChrome(isFocused: isSearchFocused)

                Button {
                    showsFilters.toggle()
                } label: {
                    Image(systemName: vm.projectLibraryNavigation.filters.activeCount == 0
                          ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(vm.projectLibraryNavigation.filters.activeCount == 0 ? BlitzUI.primaryText : BlitzUI.accent)
                        .frame(width: 18)
                }
                .blitzButton(.secondary)
                .accessibilityLabel("Sort and filter")
                .accessibilityValue(vm.projectLibraryNavigation.filters.activeCount == 0
                    ? vm.projectLibraryNavigation.filters.sort.rawValue
                    : "\(vm.projectLibraryNavigation.filters.activeCount) filters")
                .help("Sort and filter recordings")
                .popover(isPresented: $showsFilters, arrowEdge: .bottom) {
                    ProjectLibraryFiltersView(filters: $vm.projectLibraryNavigation.filters)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if vm.projectLibraryNavigation.filters.activeCount > 0 {
                HStack {
                    Text("\(filteredProjects.count) matching · \(vm.projectLibraryNavigation.filters.activeCount) filters")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                    Spacer()
                    Button {
                        vm.projectLibraryNavigation.filters = .init(sort: vm.projectLibraryNavigation.filters.sort)
                    } label: { Label("Clear", systemImage: "xmark") }
                    .blitzButton(.secondary)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            let visibleProjects = filteredProjects
            let sharedProjectPaths = Set(visibleProjects.map(\.projectPath).filter { sharing.sharedURL(forProject: $0) != nil })
            let hasQuery = !vm.projectLibraryNavigation.searchText.isEmpty || vm.projectLibraryNavigation.filters.activeCount > 0
            let index = vm.folderIndex
            List(selection: $vm.projectLibraryNavigation.selectedProjectIDs) {
                if let scope = vm.projectLibraryNavigation.folderScope {
                    let nodes = ProjectFolderTree.roots(.init(projects: visibleProjects, index: index, includesEmpty: !hasQuery))
                        .flatMap(\.flattened)
                    ForEach(nodes.first { $0.path == scope.path }?.flattened ?? []) { node in
                        folderSections(.init(node: node, scope: scope, index: index,
                                             sharedProjectPaths: sharedProjectPaths, showsEmpty: !hasQuery))
                    }
                } else {
                    let groups = ProjectLibraryDayGroups.groups(.init(
                        projects: visibleProjects,
                        groupsByDay: vm.projectLibraryNavigation.filters.sort.isChronological,
                        now: Date(), calendar: .current
                    ))
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.projects, id: \.id) { project in
                                let resolved = index.resolved(project)
                                projectRow(.init(
                                    project: project, groupsByDay: group.groupsByDay,
                                    isShared: sharedProjectPaths.contains(project.projectPath),
                                    title: resolved.folder == nil ? displayTitle(project) : ProjectFolderTitle.baseTitle(resolved.title),
                                    lessonNumber: nil,
                                    context: resolved.folder.map { folder in
                                        ([folder.name] + [resolved.code?.formatted].compactMap { $0 }).joined(separator: " · ")
                                    },
                                    isDuplicateLesson: false
                                ))
                            }
                        } header: {
                            if !group.title.isEmpty { BlitzUI.sectionLabel(group.title) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .prefersDefaultFocus(true, in: libraryFocus)
            .defaultFocus($isSearchFocused, false)
            .onDeleteCommand {
                guard workPolicy.loadsLocalProjects else { return }
                queueDeletion(projects(for: vm.projectLibraryNavigation.selectedProjectIDs))
            }
            .contextMenu(forSelectionType: UUID.self) { _ in
                EmptyView()
            } primaryAction: { selection in
                let projects = projects(for: selection)
                if !vm.projectTrash.isWorking, projects.count == 1, let project = projects.first {
                    vm.openProject(project)
                }
            }
        }
        .frame(width: ProjectLibrarySidebarLayout.width)
        .background(BlitzMaterialBackground(kind: .content))
        .focusScope(libraryFocus)
        .onAppear {
            isSearchFocused = false
            DispatchQueue.main.async {
                isSearchFocused = false
            }
        }
    }

    struct RowRequest {
        let project: RecordingProjectHistory.Entry
        let groupsByDay: Bool
        let isShared: Bool
        let title: String
        let lessonNumber: String?
        let context: String?
        let isDuplicateLesson: Bool
    }


    func projectRow(_ request: RowRequest) -> some View {
        let project = request.project
        let metadata = metadataByProjectID[project.id] ?? .empty
        return ProjectLibrarySidebarRow(configuration: .init(
            title: request.title, metadata: metadata,
            lessonNumber: request.lessonNumber,
            isDuplicateLesson: request.isDuplicateLesson,
            detail: [request.context, request.groupsByDay
                ? project.recordedAt.formatted(date: .omitted, time: .shortened)
                : project.recordedAt.formatted(date: .abbreviated, time: .omitted),
                metadata.videoQuality?.label.components(separatedBy: " · ").first
            ].compactMap { $0 }.joined(separator: " · "),
            match: transcriptMatches[project.id]?.first.map { "\(ProjectLibraryMetadata.durationLabel($0.time)) · \($0.text)" },
            isShared: request.isShared,
            isSelected: vm.projectLibraryNavigation.selectedProjectIDs.contains(project.id)
        ))
        .blitzContextMenu(projectMenu(project.id))
        .listRowInsets(ProjectLibrarySidebarLayout.rowInsets)
        .tag(project.id)
        .draggable(project.id.uuidString)
    }

    func projectMenu(_ id: UUID?) -> BlitzContextMenu {
        BlitzContextMenu(willOpen: {
            if let id, !vm.projectLibraryNavigation.selectedProjectIDs.contains(id) {
                vm.projectLibraryNavigation.selectedProjectIDs = [id]
            }
        }, entries: {
            projectMenuEntries(id.map { vm.projectLibraryNavigation.selectedProjectIDs.contains($0)
                ? vm.projectLibraryNavigation.selectedProjectIDs : [$0] } ?? vm.projectLibraryNavigation.selectedProjectIDs)
        })
    }

    func projectMenuEntries(_ selection: Set<UUID>) -> [BlitzMenuEntry] {
        let projects = projects(for: selection)
        guard !projects.isEmpty, !vm.projectTrash.isWorking else { return [] }
        var entries: [BlitzMenuEntry] = []
        if projects.count == 1, let project = projects.first {
            entries.append(.item(.init(title: "Edit Recording", systemImage: BlitzSymbols.edit,
                                       isEnabled: vm.canOpenProjectEditor, action: { vm.openProject(project) })))
            entries.append(.item(.init(title: "Rename…", systemImage: BlitzSymbols.rename, action: { beginRename(project) })))
            if let url = sharing.sharedURL(forProject: project.projectPath) {
                entries.append(.item(.init(title: "Copy Watch Link", systemImage: BlitzSymbols.share,
                                           action: { BlitzClipboard.copyInBackground(url.absoluteString) })))
            }
            entries.append(.divider)
        }
        entries.append(.item(.init(title: projects.count == 1 ? "Show in Finder" : "Show \(projects.count) in Finder",
                                   systemImage: BlitzSymbols.folder, action: { vm.revealProjects(projects) })))
        entries.append(.section("Move to folder"))
        for node in vm.folderTree.flatMap(\.flattened) {
            entries.append(.item(.init(title: node.path.displayPath, systemImage: BlitzSymbols.folder, action: {
                vm.moveIntoFolder(.init(projects: projects, destination: vm.folderDestination(node), path: node.path))
            })))
        }
        entries.append(.item(.init(title: "New Folder…", systemImage: "folder.badge.plus",
                                   action: { vm.presentFolderPrompt(.create(parent: nil, moving: projects)) })))
        if projects.contains(where: { vm.folderIndex.resolved($0).folder != nil }) {
            entries.append(.item(.init(title: "Remove from Folder", systemImage: "folder.badge.minus",
                                       action: { vm.removeFromFolder(projects) })))
        }
        entries.append(.divider)
        entries.append(.item(.init(title: projects.count == 1 ? "Move to Trash" : "Move \(projects.count) to Trash",
                                   systemImage: BlitzSymbols.delete, isDestructive: true, action: { queueDeletion(projects) })))
        return entries
    }
}

enum ProjectLibrarySidebarLayout {
    static let width: CGFloat = 360
    static let rowInsets = EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
    static let rowPadding: CGFloat = 6
    static let thumbnailRadius: CGFloat = 6
    /// Concentric with the thumbnail: inner radius plus padding.
    static let rowRadius: CGFloat = thumbnailRadius + rowPadding
    static let thumbnailSize = CGSize(width: 96, height: 54)
}

struct ProjectLibrarySidebarRow: View {
    struct Configuration {
        let title: String
        let metadata: ProjectLibraryMetadata
        let lessonNumber: String?
        let isDuplicateLesson: Bool
        let detail: String
        let match: String?
        let isShared: Bool
        let isSelected: Bool
    }

    let configuration: Configuration
    @State private var isHovering = false

    @ViewBuilder private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.rowRadius, style: .continuous)
        if configuration.isSelected {
            BlitzSelectedBackground(cornerRadius: Layout.rowRadius)
        } else {
            shape.fill(isHovering ? BlitzUI.quietFill : .clear)
        }
    }

    private typealias Layout = ProjectLibrarySidebarLayout

    var body: some View {
        HStack(spacing: 10) {
            if let lessonNumber = configuration.lessonNumber {
                Text(lessonNumber)
                    .font(BlitzType.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(configuration.isDuplicateLesson ? BlitzUI.warning : BlitzUI.tertiaryText)
                    .frame(width: 18, alignment: .center)
                    .fixedSize()
                    .accessibilityLabel("Lesson \(lessonNumber)")
                    .help(configuration.isDuplicateLesson ? "Another recording uses this lesson number" : "Lesson \(lessonNumber)")

            }
            ProjectLibraryThumbnail(configuration: .init(
                metadata: configuration.metadata, width: Layout.thumbnailSize.width, height: Layout.thumbnailSize.height,
                cornerRadius: Layout.thumbnailRadius, showsDuration: false
            ))
            VStack(alignment: .leading, spacing: 5) {
                Text(configuration.title)
                    .font(BlitzType.navigation)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let match = configuration.match {
                    Text(match)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.accent)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(configuration.detail).lineLimit(1)
                    Spacer(minLength: 0)
                    if configuration.isShared {
                        Image(systemName: BlitzSymbols.share)
                            .font(BlitzType.symbol(10))
                            .accessibilityLabel("Shared")
                            .help("Has a watch link")
                    }
                    if let duration = configuration.metadata.durationSeconds {
                        Text(ProjectLibraryMetadata.durationLabel(duration))
                            .monospacedDigit()
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Layout.rowPadding)
        .frame(minHeight: Layout.thumbnailSize.height + Layout.rowPadding * 2)
        .background { rowBackground }
        .background(ProjectLibraryListHighlightSuppressor())
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .accessibilityAddTraits(configuration.isSelected ? .isSelected : [])
    }
}

private struct ProjectLibraryListHighlightSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.suppressHighlight()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async { [weak self] in self?.suppressHighlight() }
        }

        func suppressHighlight() {
            var ancestor = superview
            while let view = ancestor {
                if let tableView = view as? NSTableView {
                    if tableView.selectionHighlightStyle != .none {
                        tableView.selectionHighlightStyle = .none
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
