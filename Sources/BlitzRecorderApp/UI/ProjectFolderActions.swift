import SwiftUI

struct ProjectFolderDropRequest {
    let ids: [String]
    let destination: ProjectFolderMoves.Destination
}

extension RecorderViewModel {
    var folderIndex: ProjectFolderIndex {
        ProjectFolderIndex(.init(projects: recentProjects, pins: ProjectFolderStore.shared.pins))
    }

    var folderTree: [ProjectFolderTree.Node] {
        ProjectFolderTree.roots(.init(projects: recentProjects, index: folderIndex, includesEmpty: true))
    }

    func folderDestination(_ node: ProjectFolderTree.Node) -> ProjectFolderMoves.Destination {
        .folder(path: node.path, module: node.isNumbered ? node.lastModule : nil, before: nil)
    }

    func recordTarget(_ node: ProjectFolderTree.Node) -> ProjectFolderRecordTarget {
        .init(path: node.path, module: node.isNumbered ? node.lastModule : nil)
    }

    func presentFolderPrompt(_ prompt: ProjectFolderPrompt) {
        if case .rename(let path) = prompt { folderNameDraft = path.name } else { folderNameDraft = "" }
        folderPrompt = prompt
    }

    func addModule(_ node: ProjectFolderTree.Node) {
        ProjectFolderStore.shared.pinModule(.init(path: node.path, module: node.nextModule))
        expandedFolderIDs.insert(node.id)
    }

    func numberAsLessons(_ node: ProjectFolderTree.Node) {
        ProjectFolderStore.shared.pinModule(.init(path: node.path, module: 1))
        moveProjects(.init(
            titles: ProjectFolderMoves.titles(.init(
                moving: node.projects, destination: .folder(path: node.path, module: 1, before: nil),
                index: folderIndex, library: recentProjects
            )),
            message: "Numbered \(node.path.name) as lessons", folderRename: nil
        ))
    }

    func deleteFolder(_ node: ProjectFolderTree.Node) {
        ProjectFolderStore.shared.remove(node.path)
        clearFolderReferences(inside: node.path)
    }

    func ungroupFolder(_ node: ProjectFolderTree.Node) {
        let titles = ProjectFolderMoves.titles(.init(
            moving: node.allProjects, destination: .loose, index: folderIndex, library: recentProjects
        ))
        deleteFolder(node)
        moveProjects(.init(titles: titles, message: "Ungrouped \(node.path.name)", folderRename: nil))
    }

    private func clearFolderReferences(inside path: ProjectFolderPath) {
        if folderRecordTarget?.path.hasPrefix(path) == true { folderRecordTarget = nil }
        if projectLibraryNavigation.folderScope?.path.hasPrefix(path) == true { projectLibraryNavigation.folderScope = nil }
    }

    struct FolderMoveRequest {
        let projects: [RecordingProjectHistory.Entry]
        let destination: ProjectFolderMoves.Destination
        let path: ProjectFolderPath
    }

    func moveIntoFolder(_ request: FolderMoveRequest) {
        ProjectFolderStore.shared.pin(request.path)
        moveProjects(.init(
            titles: ProjectFolderMoves.titles(.init(
                moving: request.projects, destination: request.destination, index: folderIndex, library: recentProjects
            )),
            message: request.projects.count == 1
                ? "Moved to \(request.path.name)" : "Moved \(request.projects.count) recordings to \(request.path.name)",
            folderRename: nil
        ))
    }

    func removeFromFolder(_ projects: [RecordingProjectHistory.Entry]) {
        moveProjects(.init(
            titles: ProjectFolderMoves.titles(.init(moving: projects, destination: .loose, index: folderIndex, library: recentProjects)),
            message: projects.count == 1 ? "Removed from folder" : "Removed \(projects.count) recordings from folder",
            folderRename: nil
        ))
    }

    func dropProjects(_ request: ProjectFolderDropRequest) -> Bool {
        let dropped = Set(request.ids.compactMap(UUID.init(uuidString:)))
        guard !dropped.isEmpty, !projectTrash.isWorking else { return false }
        let selection = projectLibraryNavigation.selectedProjectIDs
        let ids = dropped.isSubset(of: selection) ? selection : dropped
        let moving = recentProjects.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return false }
        switch request.destination {
        case .folder(let path, _, _):
            moveIntoFolder(.init(projects: moving, destination: request.destination, path: path))
        case .loose:
            removeFromFolder(moving)
        }
        return true
    }

    func folderPromptAffectedCount(_ prompt: ProjectFolderPrompt) -> Int {
        guard case .rename(let path) = prompt else { return 0 }
        let index = folderIndex
        return recentProjects.filter { index.resolved($0).folder?.hasPrefix(path) == true }.count
    }

    func commitFolderPrompt(_ prompt: ProjectFolderPrompt) {
        let name = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        folderPrompt = nil
        guard ProjectFolderPath.isValidName(name) else { return }
        switch prompt {
        case .create(let parent, let moving):
            guard let path = parent?.appending(name) ?? ProjectFolderPath([name]) else { return }
            ProjectFolderStore.shared.pin(path)
            expandedFolderIDs.formUnion((path.parent?.ancestorsAndSelf ?? []).map(\.id))
            if !moving.isEmpty {
                moveIntoFolder(.init(projects: moving, destination: .folder(path: path, module: nil, before: nil), path: path))
            }
        case .rename(let from):
            guard let to = from.parent?.appending(name) ?? ProjectFolderPath([name]), to.segments != from.segments else { return }
            let replacement = ProjectFolderPath.PrefixReplacement(from: from, to: to)
            moveProjects(.init(
                titles: ProjectFolderMoves.titles(ProjectFolderMoves.RenameRequest(
                    replacement: replacement, index: folderIndex, library: recentProjects
                )),
                message: "Renamed \(from.name) to \(name)", folderRename: replacement
            ))
            if let scope = projectLibraryNavigation.folderScope, scope.path.hasPrefix(from) {
                projectLibraryNavigation.folderScope = scope.replacingPrefix(replacement)
            }
            expandedFolderIDs = Set(expandedFolderIDs.map { id in
                id == from.id || id.hasPrefix(from.id + "/") ? to.id + id.dropFirst(from.id.count) : id
            })
        }
    }
}

struct ProjectFolderMenu: View {
    @Bindable var vm: RecorderViewModel
    let node: ProjectFolderTree.Node

    var body: some View {
        Button(node.isNumbered ? "Record Next Lesson" : "Record Here", systemImage: "record.circle") {
            vm.recordInFolder(vm.recordTarget(node))
        }
        .disabled(vm.state != .idle)
        Button("New Folder Inside…", systemImage: "folder.badge.plus") {
            vm.presentFolderPrompt(.create(parent: node.path, moving: []))
        }
        if node.isNumbered {
            Button("New Module", systemImage: "plus") { vm.addModule(node) }
        } else {
            Button("Number as Lessons", systemImage: "list.number") { vm.numberAsLessons(node) }
        }
        Button("Rename Folder…", systemImage: "pencil") { vm.presentFolderPrompt(.rename(node.path)) }
        Divider()
        Button("Export All", systemImage: "square.and.arrow.up") { vm.exportFolder(node.allProjects) }
            .disabled(node.allProjects.isEmpty || vm.isExporting || vm.folderExportStatus != nil || vm.state != .idle)
        Button("Show in Finder", systemImage: "folder") { vm.revealProjects(node.allProjects) }
            .disabled(node.allProjects.isEmpty)
        Divider()
        if node.allProjects.isEmpty {
            Button("Delete Folder", systemImage: "trash", role: .destructive) { vm.deleteFolder(node) }
        } else {
            Button("Ungroup", systemImage: "folder.badge.minus") { vm.ungroupFolder(node) }
        }
    }
}

struct ProjectModuleMenu: View {
    @Bindable var vm: RecorderViewModel
    let node: ProjectFolderTree.Node
    let module: ProjectFolderTree.Module

    var body: some View {
        Button("Record Next Lesson", systemImage: "record.circle") {
            vm.recordInFolder(.init(path: node.path, module: module.id))
        }
        .disabled(vm.state != .idle)
        Button("New Module", systemImage: "plus") { vm.addModule(node) }
    }
}

struct ProjectMoveToFolderMenu: View {
    @Bindable var vm: RecorderViewModel
    let projects: [RecordingProjectHistory.Entry]

    var body: some View {
        let folders = vm.folderTree.flatMap(\.flattened)
        let index = vm.folderIndex
        Menu("Move to Folder") {
            ForEach(folders) { node in
                Button(node.path.displayPath) {
                    vm.moveIntoFolder(.init(projects: projects, destination: vm.folderDestination(node), path: node.path))
                }
            }
            if !folders.isEmpty { Divider() }
            Button("New Folder…") { vm.presentFolderPrompt(.create(parent: nil, moving: projects)) }
        }
        if projects.contains(where: { index.resolved($0).folder != nil }) {
            Button("Remove from Folder", systemImage: "folder.badge.minus") { vm.removeFromFolder(projects) }
        }
    }
}
