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
                .padding(.horizontal, 11)
                .frame(height: BlitzControlMetrics.height(.regular))
                .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: BlitzControlMetrics.radius, style: .continuous)
                        .strokeBorder(isSearchFocused ? BlitzUI.mint.opacity(0.65) : BlitzUI.panelStroke, lineWidth: 1)
                }

                Button {
                    showsFilters.toggle()
                } label: {
                    Image(systemName: vm.projectLibraryNavigation.filters.activeCount == 0
                          ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(vm.projectLibraryNavigation.filters.activeCount == 0 ? BlitzUI.primaryText : BlitzUI.mint)
                        .frame(width: 18)
                }
                .blitzButton(.secondary)
                .accessibilityLabel("Sort and filter")
                .accessibilityValue(vm.projectLibraryNavigation.filters.activeCount == 0
                    ? vm.projectLibraryNavigation.filters.sort.rawValue
                    : "\(vm.projectLibraryNavigation.filters.activeCount) filters")
                .help("Sort and filter recordings")
                .popover(isPresented: $showsFilters, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sort").font(BlitzType.section)
                            BlitzDropdown(configuration: .init(
                                title: "Sort projects", selection: $vm.projectLibraryNavigation.filters.sort,
                                options: ProjectLibraryFilters.Sort.allCases.map { .init(value: $0, title: $0.rawValue, detail: nil) },
                                menuWidth: 220
                            ))
                        }
                        .padding([.horizontal, .top], 16)
                        Rectangle().fill(BlitzUI.separator).frame(height: 1)
                        ProjectLibraryFiltersView(filters: $vm.projectLibraryNavigation.filters)
                    }
                    .background(BlitzUI.panelBackground)
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

            Rectangle().fill(BlitzUI.separator).frame(height: 1)

            let visibleProjects = filteredProjects
            let sharedProjectPaths = Set(visibleProjects.map(\.projectPath).filter { sharing.sharedURL(forProject: $0) != nil })
            List(selection: $vm.projectLibraryNavigation.selectedProjectIDs) {
                ForEach(ProjectLibraryDayGroups.groups(.init(
                    projects: visibleProjects, groupsByDay: vm.projectLibraryNavigation.filters.sort.isChronological,
                    now: Date(), calendar: .current
                )), id: \.title) { group in
                    Section {
                        ForEach(group.projects, id: \.id) { project in
                            let metadata = metadataByProjectID[project.id] ?? .empty
                            ProjectLibrarySidebarRow(configuration: .init(
                                title: displayTitle(project),
                                metadata: metadata,
                                detail: [
                                    group.groupsByDay
                                        ? project.recordedAt.formatted(date: .omitted, time: .shortened)
                                        : project.recordedAt.formatted(date: .abbreviated, time: .omitted),
                                    metadata.videoQuality?.label.components(separatedBy: " · ").first
                                ].compactMap { $0 }.joined(separator: " · "),
                                match: transcriptMatches[project.id]?.first.map { "\(SilenceTime.label($0.time)) · \($0.text)" },
                                isShared: sharedProjectPaths.contains(project.projectPath),
                                isSelected: vm.projectLibraryNavigation.selectedProjectIDs.contains(project.id)
                            ))
                            .tag(project.id)
                        }
                    } header: {
                        if !group.title.isEmpty {
                            Text(group.title)
                                .font(BlitzType.captionEmphasis)
                                .foregroundStyle(BlitzUI.secondaryText)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(BlitzUI.projectLibraryBackground)
            .prefersDefaultFocus(true, in: libraryFocus)
            .defaultFocus($isSearchFocused, false)
            .onDeleteCommand {
                queueDeletion(projects(for: vm.projectLibraryNavigation.selectedProjectIDs))
            }
            .contextMenu(forSelectionType: UUID.self) { selection in
                projectContextMenu(selection)
            } primaryAction: { selection in
                let projects = projects(for: selection)
                if !vm.projectTrash.isWorking, projects.count == 1, let project = projects.first {
                    vm.openProject(project)
                }
            }
        }
        .frame(width: 340)
        .background(BlitzUI.projectLibraryBackground)
        .focusScope(libraryFocus)
        .onAppear {
            isSearchFocused = false
            DispatchQueue.main.async {
                isSearchFocused = false
            }
        }
    }

    @ViewBuilder
    func projectContextMenu(
        _ selection: Set<UUID>
    ) -> some View {
        let projects = projects(for: selection)

        Group {
            if projects.count == 1, let project = projects.first {
                if let url = sharing.sharedURL(forProject: project.projectPath) {
                    Button("Copy share link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    Button("Open shared video") { NSWorkspace.shared.open(url) }
                    Divider()
                }
                Button("Edit recording") {
                    vm.openProject(project)
                }
                .disabled(vm.state != .idle)

                Button {
                    beginRename(project)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }

            if !projects.isEmpty {
                Button {
                    vm.revealProjects(projects)
                } label: {
                    Label(
                        projects.count == 1 ? "Show in Finder" : "Show Selected in Finder",
                        systemImage: "folder"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    queueDeletion(projects)
                } label: {
                    Label(
                        projects.count == 1
                            ? "Move to Trash"
                            : "Move \(projects.count) Projects to Trash",
                        systemImage: "trash"
                    )
                }
            }
        }
        .disabled(vm.projectTrash.isWorking)
    }
}

private struct ProjectLibrarySidebarRow: View {
    struct Configuration {
        let title: String
        let metadata: ProjectLibraryMetadata
        let detail: String
        let match: String?
        let isShared: Bool
        let isSelected: Bool
    }

    let configuration: Configuration
    @State private var isHovering = false

    private var rowFill: Color {
        if configuration.isSelected { return BlitzUI.selectedFill }
        return isHovering ? BlitzUI.hoverFill : .clear
    }

    var body: some View {
        HStack(spacing: 12) {
            ProjectLibraryThumbnail(configuration: .init(
                metadata: configuration.metadata, width: 96, height: 54, cornerRadius: 6, showsDuration: true
            ))
            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.title)
                    .font(BlitzType.strong)
                    .foregroundStyle(BlitzUI.primaryText)
                    .lineLimit(2)
                if let match = configuration.match {
                    Text(match)
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.mint)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(configuration.detail).lineLimit(1)
                    if configuration.isShared {
                        Image(systemName: "link")
                            .foregroundStyle(BlitzUI.mint)
                            .accessibilityLabel("Shared")
                            .help("Has a watch link")
                    }
                }
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(rowFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
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
