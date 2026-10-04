import AppKit
import SwiftUI

enum ProjectFolderPrompt: Identifiable {
    case create(parent: ProjectFolderPath?, moving: [RecordingProjectHistory.Entry])
    case rename(ProjectFolderPath)

    var id: String {
        switch self {
        case .create(let parent, _): "create-\(parent?.id ?? "")"
        case .rename(let path): "rename-\(path.id)"
        }
    }

    var title: String {
        switch self {
        case .create(let parent?, _): "New folder in \(parent.name)"
        case .create(nil, let moving): moving.isEmpty ? "New folder" : "New folder from \(moving.count) recordings"
        case .rename: "Rename folder"
        }
    }

    var actionTitle: String {
        switch self {
        case .create: "Create"
        case .rename: "Rename"
        }
    }
}

extension ProjectLibraryView {
    var folderIndex: ProjectFolderIndex {
        ProjectFolderIndex(.init(projects: vm.recentProjects, pins: folderStore.pins))
    }

    var allFolders: [ProjectFolderTree.Node] {
        ProjectFolderTree.roots(.init(projects: vm.recentProjects, index: folderIndex, includesEmpty: true))
            .flatMap(\.flattened)
    }

    struct FolderNodeRequest {
        let node: ProjectFolderTree.Node
        let index: ProjectFolderIndex
        let sharedProjectPaths: Set<String>
    }

    func folderNode(_ request: FolderNodeRequest) -> AnyView {
        let node = request.node
        return AnyView(DisclosureGroup(isExpanded: Binding(
            get: { !collapsedFolderIDs.contains(node.id) },
            set: { expanded in
                if expanded { collapsedFolderIDs.remove(node.id) } else { collapsedFolderIDs.insert(node.id) }
            }
        )) {
            ForEach(node.children) { child in
                folderNode(.init(node: child, index: request.index, sharedProjectPaths: request.sharedProjectPaths))
            }
            ForEach(node.modules) { module in
                moduleHeader(.init(node: node, module: module))
                if module.projects.isEmpty {
                    emptyRow(.init(id: "empty-\(node.id)-\(module.id)",
                                   destination: .folder(path: node.path, module: module.id, before: nil)))
                }
                ForEach(module.projects, id: \.id) { project in
                    projectRow(.init(
                        project: project, groupsByDay: false,
                        isShared: request.sharedProjectPaths.contains(project.projectPath),
                        folderTitle: request.index.resolved(project),
                        isDuplicateLesson: module.duplicateLessonIDs.contains(project.id)
                    ))
                    .background(dropFill("row-\(project.id)"), in: .rect(cornerRadius: BlitzUI.controlRadius))
                    .projectDropTarget(.init(id: "row-\(project.id)", target: $dropTargetID) { ids in
                        dropProjects(.init(ids: ids, destination: .folder(path: node.path, module: module.id, before: project.id)))
                    })
                }
            }
            ForEach(node.projects, id: \.id) { project in
                projectRow(.init(
                    project: project, groupsByDay: false,
                    isShared: request.sharedProjectPaths.contains(project.projectPath),
                    folderTitle: request.index.resolved(project), isDuplicateLesson: false
                ))
                .background(dropFill("row-\(project.id)"), in: .rect(cornerRadius: BlitzUI.controlRadius))
                .projectDropTarget(.init(id: "row-\(project.id)", target: $dropTargetID) { ids in
                    dropProjects(.init(ids: ids, destination: .folder(path: node.path, module: nil, before: nil)))
                })
            }
            if node.children.isEmpty && node.modules.isEmpty && node.projects.isEmpty {
                emptyRow(.init(id: "empty-\(node.id)", destination: .folder(path: node.path, module: nil, before: nil)))
            }
        } label: {
            folderLabel(node)
        })
    }

    private struct EmptyRowRequest {
        let id: String
        let destination: ProjectFolderMoves.Destination
    }

    private func emptyRow(_ request: EmptyRowRequest) -> some View {
        Text("Drag recordings here, or record into this folder")
            .font(BlitzType.caption)
            .foregroundStyle(BlitzUI.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 8)
            .background(dropFill(request.id), in: .rect(cornerRadius: BlitzUI.controlRadius))
            .projectDropTarget(.init(id: request.id, target: $dropTargetID) { ids in
                dropProjects(.init(ids: ids, destination: request.destination))
            })
    }

    private func folderDestination(_ node: ProjectFolderTree.Node) -> ProjectFolderMoves.Destination {
        .folder(path: node.path, module: node.isNumbered ? node.lastModule : nil, before: nil)
    }

    private func recordTarget(_ node: ProjectFolderTree.Node) -> ProjectFolderRecordTarget {
        .init(path: node.path, module: node.isNumbered ? node.lastModule : nil)
    }

    private func folderLabel(_ node: ProjectFolderTree.Node) -> some View {
        let count = node.allProjects.count
        let target = recordTarget(node)
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(BlitzUI.secondaryText)
            Text(node.path.name)
                .font(BlitzType.strong)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .monospacedDigit()
                .accessibilityLabel(count == 1 ? "1 recording" : "\(count) recordings")
            Button {
                folderNameDraft = node.path.name
                folderPrompt = .rename(node.path)
            } label: {
                Image(systemName: "pencil")
            }
            .blitzButton(.quiet)
            .controlSize(.mini)
            .help("Rename \(node.path.displayPath)")
            .accessibilityLabel("Rename folder \(node.path.displayPath)")
            if !node.isNumbered {
                recordButton(.init(target: target, isTarget: vm.folderRecordTarget == target,
                                   help: "Record into \(node.path.displayPath)"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(dropFill("folder-\(node.id)"), in: .rect(cornerRadius: BlitzUI.controlRadius))
        .contentShape(.rect)
        .projectDropTarget(.init(id: "folder-\(node.id)", target: $dropTargetID) { ids in
            dropProjects(.init(ids: ids, destination: folderDestination(node)))
        })
        .contextMenu { folderMenu(node) }
        .help("Drop recordings here to move them into \(node.path.displayPath)")
    }

    private struct RecordButtonRequest {
        let target: ProjectFolderRecordTarget
        let isTarget: Bool
        let help: String
    }

    private func recordButton(_ request: RecordButtonRequest) -> some View {
        Button {
            vm.recordInFolder(request.target)
        } label: {
            Image(systemName: request.isTarget ? "record.circle.fill" : "record.circle")
                .foregroundStyle(request.isTarget ? BlitzUI.mint : BlitzUI.secondaryText)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(vm.state != .idle)
        .help(request.help)
        .accessibilityLabel(request.help)
    }

    private struct ModuleHeaderRequest {
        let node: ProjectFolderTree.Node
        let module: ProjectFolderTree.Module
    }

    private func moduleHeader(_ request: ModuleHeaderRequest) -> some View {
        let target = ProjectFolderRecordTarget(path: request.node.path, module: request.module.id)
        let dropID = "module-\(request.node.id)-\(request.module.id)"
        let name = "Module \(ProjectLessonCode.number(request.module.id))"
        return HStack(spacing: 8) {
            Text(name)
                .font(BlitzType.captionEmphasis)
                .foregroundStyle(BlitzUI.secondaryText)
            if !request.module.duplicateLessonIDs.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.warning)
                    .help("Two recordings share a lesson number. Drag one to reorder and renumber this module.")
                    .accessibilityLabel("Duplicate lesson numbers")
            }
            Spacer(minLength: 4)
            recordButton(.init(target: target, isTarget: vm.folderRecordTarget == target,
                               help: "Record the next lesson in \(name)"))
        }
        .padding(.top, 6)
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .background(dropFill(dropID), in: .rect(cornerRadius: BlitzUI.controlRadius))
        .contentShape(.rect)
        .projectDropTarget(.init(id: dropID, target: $dropTargetID) { ids in
            dropProjects(.init(ids: ids, destination: .folder(path: request.node.path, module: request.module.id, before: nil)))
        })
        .contextMenu {
            Button("Record Next Lesson", systemImage: "record.circle") { vm.recordInFolder(target) }
                .disabled(vm.state != .idle)
            Button("New Module", systemImage: "plus") {
                folderStore.pinModule(.init(path: request.node.path, module: request.node.nextModule))
            }
        }
    }

    @ViewBuilder
    private func folderMenu(_ node: ProjectFolderTree.Node) -> some View {
        Button(node.isNumbered ? "Record Next Lesson" : "Record Here", systemImage: "record.circle") {
            vm.recordInFolder(recordTarget(node))
        }
        .disabled(vm.state != .idle)
        Button("New Folder Inside…", systemImage: "folder.badge.plus") {
            folderNameDraft = ""
            folderPrompt = .create(parent: node.path, moving: [])
        }
        if node.isNumbered {
            Button("New Module", systemImage: "plus") {
                folderStore.pinModule(.init(path: node.path, module: node.nextModule))
                collapsedFolderIDs.remove(node.id)
            }
        } else {
            Button("Number as Lessons", systemImage: "list.number") {
                folderStore.pinModule(.init(path: node.path, module: 1))
                vm.moveProjects(.init(
                    titles: ProjectFolderMoves.titles(.init(
                        moving: node.projects, destination: .folder(path: node.path, module: 1, before: nil),
                        index: folderIndex, library: vm.recentProjects
                    )),
                    message: "Numbered \(node.path.name) as lessons", folderRename: nil
                ))
            }
        }
        Button("Rename Folder…", systemImage: "pencil") {
            folderNameDraft = node.path.name
            folderPrompt = .rename(node.path)
        }
        Divider()
        Button("Export All", systemImage: "square.and.arrow.up") { vm.exportFolder(node.allProjects) }
            .disabled(node.allProjects.isEmpty || vm.isExporting || vm.folderExportStatus != nil || vm.state != .idle)
        Button("Show in Finder", systemImage: "folder") { vm.revealProjects(node.allProjects) }
            .disabled(node.allProjects.isEmpty)
        Divider()
        if node.allProjects.isEmpty {
            Button("Delete Folder", systemImage: "trash", role: .destructive) {
                folderStore.remove(node.path)
                clearRecordTarget(inside: node.path)
            }
        } else {
            Button("Ungroup", systemImage: "folder.badge.minus") {
                let titles = ProjectFolderMoves.titles(.init(
                    moving: node.allProjects, destination: .loose, index: folderIndex, library: vm.recentProjects
                ))
                folderStore.remove(node.path)
                clearRecordTarget(inside: node.path)
                vm.moveProjects(.init(titles: titles, message: "Ungrouped \(node.path.name)", folderRename: nil))
            }
        }
    }

    private func clearRecordTarget(inside path: ProjectFolderPath) {
        if vm.folderRecordTarget?.path.hasPrefix(path) == true { vm.folderRecordTarget = nil }
    }

    @ViewBuilder
    func moveToFolderMenu(_ projects: [RecordingProjectHistory.Entry]) -> some View {
        let folders = allFolders
        let index = folderIndex
        Menu("Move to Folder") {
            ForEach(folders) { node in
                Button(node.path.displayPath) {
                    move(.init(projects: projects, destination: folderDestination(node), path: node.path))
                }
            }
            if !folders.isEmpty { Divider() }
            Button("New Folder…") {
                folderNameDraft = ""
                folderPrompt = .create(parent: nil, moving: projects)
            }
        }
        if projects.contains(where: { index.resolved($0).folder != nil }) {
            Button("Remove from Folder", systemImage: "folder.badge.minus") { removeFromFolder(projects) }
        }
    }

    private struct MoveRequest {
        let projects: [RecordingProjectHistory.Entry]
        let destination: ProjectFolderMoves.Destination
        let path: ProjectFolderPath
    }

    private func move(_ request: MoveRequest) {
        folderStore.pin(request.path)
        vm.moveProjects(.init(
            titles: ProjectFolderMoves.titles(.init(
                moving: request.projects, destination: request.destination, index: folderIndex, library: vm.recentProjects
            )),
            message: request.projects.count == 1
                ? "Moved to \(request.path.name)" : "Moved \(request.projects.count) recordings to \(request.path.name)",
            folderRename: nil
        ))
    }

    struct DropRequest {
        let ids: [String]
        let destination: ProjectFolderMoves.Destination
    }

    func dropProjects(_ request: DropRequest) -> Bool {
        let dropped = Set(request.ids.compactMap(UUID.init(uuidString:)))
        guard !dropped.isEmpty, !vm.projectTrash.isWorking else { return false }
        let selection = vm.projectLibraryNavigation.selectedProjectIDs
        let ids = dropped.isSubset(of: selection) ? selection : dropped
        let moving = vm.recentProjects.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return false }
        switch request.destination {
        case .folder(let path, _, _):
            move(.init(projects: moving, destination: request.destination, path: path))
        case .loose:
            removeFromFolder(moving)
        }
        return true
    }

    private func removeFromFolder(_ projects: [RecordingProjectHistory.Entry]) {
        vm.moveProjects(.init(
            titles: ProjectFolderMoves.titles(.init(moving: projects, destination: .loose, index: folderIndex, library: vm.recentProjects)),
            message: projects.count == 1 ? "Removed from folder" : "Removed \(projects.count) recordings from folder",
            folderRename: nil
        ))
    }

    func folderPromptAffectedCount(_ prompt: ProjectFolderPrompt) -> Int {
        guard case .rename(let path) = prompt else { return 0 }
        let index = folderIndex
        return vm.recentProjects.filter { index.resolved($0).folder?.hasPrefix(path) == true }.count
    }

    func commitFolderPrompt(_ prompt: ProjectFolderPrompt) {
        let name = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        folderPrompt = nil
        guard ProjectFolderPath.isValidName(name) else { return }
        switch prompt {
        case .create(let parent, let moving):
            guard let path = parent?.appending(name) ?? ProjectFolderPath([name]) else { return }
            folderStore.pin(path)
            path.ancestorsAndSelf.forEach { collapsedFolderIDs.remove($0.id) }
            if !moving.isEmpty { move(.init(projects: moving, destination: .folder(path: path, module: nil, before: nil), path: path)) }
        case .rename(let from):
            guard let to = from.parent?.appending(name) ?? ProjectFolderPath([name]), to.segments != from.segments else { return }
            let replacement = ProjectFolderPath.PrefixReplacement(from: from, to: to)
            vm.moveProjects(.init(
                titles: ProjectFolderMoves.titles(ProjectFolderMoves.RenameRequest(
                    replacement: replacement, index: folderIndex, library: vm.recentProjects
                )),
                message: "Renamed \(from.name) to \(name)", folderRename: replacement
            ))
        }
    }

    func dropFill(_ id: String) -> Color {
        dropTargetID == id ? BlitzUI.selectedFill : .clear
    }
}

struct ProjectDropTargetConfiguration {
    let id: String
    let target: Binding<String?>
    let perform: ([String]) -> Bool
}

extension View {
    func projectDropTarget(_ configuration: ProjectDropTargetConfiguration) -> some View {
        dropDestination(for: String.self) { items, _ in
            configuration.target.wrappedValue = nil
            return configuration.perform(items)
        } isTargeted: { isTargeted in
            if isTargeted {
                configuration.target.wrappedValue = configuration.id
            } else if configuration.target.wrappedValue == configuration.id {
                configuration.target.wrappedValue = nil
            }
        }
    }
}

struct FolderRecordTargetMenu: View {
    @Bindable var vm: RecorderViewModel
    let folderStore = ProjectFolderStore.shared

    var body: some View {
        let index = ProjectFolderIndex(.init(projects: vm.recentProjects, pins: folderStore.pins))
        let nodes = ProjectFolderTree.roots(.init(projects: vm.recentProjects, index: index, includesEmpty: true))
            .flatMap(\.flattened)
        if !nodes.isEmpty || vm.folderRecordTarget != nil {
            let targets = nodes.flatMap { node -> [ProjectFolderRecordTarget] in
                node.isNumbered
                    ? (node.modules.isEmpty ? [1] : node.modules.map(\.id)).map { .init(path: node.path, module: $0) }
                    : [.init(path: node.path, module: nil)]
            }
            let options: [BlitzDropdownOption<ProjectFolderRecordTarget?>] = [.init(value: nil, title: "Save to Projects", detail: nil)]
                + targets.map { .init(value: $0, title: vm.recordTargetLabel($0), detail: vm.recordTargetDetail($0)) }
            HStack(spacing: 6) {
                Image(systemName: vm.folderRecordTarget == nil ? "folder" : "folder.fill")
                    .font(BlitzType.symbol(12))
                    .foregroundStyle(vm.folderRecordTarget == nil ? BlitzUI.secondaryText : BlitzUI.mint)
                    .accessibilityHidden(true)
                BlitzDropdown(configuration: .init(
                    title: "Save next take to folder",
                    selection: $vm.folderRecordTarget,
                    options: options, menuWidth: 340, width: .content
                ))
            }
            .disabled(vm.countdownRemaining != nil || vm.state != .idle)
            .help(vm.folderRecordTarget == nil
                ? "Save the next take into a folder"
                : "The next take is saved in this folder and named after it")
        }
    }
}
