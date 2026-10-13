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
    struct FolderSectionsRequest {
        let node: ProjectFolderTree.Node
        let scope: ProjectFolderScope
        let index: ProjectFolderIndex
        let sharedProjectPaths: Set<String>
        let showsEmpty: Bool
    }

    @ViewBuilder
    func folderSections(_ request: FolderSectionsRequest) -> some View {
        let node = request.node
        let modules = node.modules.filter { request.scope.module == nil || $0.id == request.scope.module }
        let prefix = node.path.segments.dropFirst(request.scope.path.segments.count).joined(separator: " › ")
        ForEach(modules) { module in
            Section {
                if module.projects.isEmpty && request.showsEmpty {
                    emptyRow(.init(id: "empty-\(node.id)-\(module.id)",
                                   destination: .folder(path: node.path, module: module.id, before: nil)))
                }
                ForEach(module.projects, id: \.id) { project in
                    let resolved = request.index.resolved(project)
                    projectRow(.init(
                        project: project, groupsByDay: false,
                        isShared: request.sharedProjectPaths.contains(project.projectPath),
                        title: ProjectFolderTitle.baseTitle(resolved.title),
                        lessonNumber: resolved.code.map { ProjectLessonCode.number($0.lesson) },
                        context: nil,
                        isDuplicateLesson: module.duplicateLessonIDs.contains(project.id)
                    ))
                    .background(dropFill("row-\(project.id)"), in: .rect(cornerRadius: ProjectLibrarySidebarLayout.rowRadius))
                    .projectDropTarget(.init(id: "row-\(project.id)", target: $dropTargetID) { ids in
                        vm.dropProjects(.init(ids: ids, destination: .folder(path: node.path, module: module.id, before: project.id)))
                    })
                }
            } header: {
                moduleHeader(.init(node: node, module: module, prefix: prefix))
            }
        }
        if request.scope.module == nil {
            let isEmpty = node.modules.isEmpty && node.projects.isEmpty && node.children.isEmpty
            if !node.projects.isEmpty || (isEmpty && request.showsEmpty) {
                Section {
                    if isEmpty {
                        emptyRow(.init(id: "empty-\(node.id)", destination: .folder(path: node.path, module: nil, before: nil)))
                    }
                    ForEach(node.projects, id: \.id) { project in
                        projectRow(.init(
                            project: project, groupsByDay: false,
                            isShared: request.sharedProjectPaths.contains(project.projectPath),
                            title: ProjectFolderTitle.baseTitle(request.index.resolved(project).title),
                            lessonNumber: nil, context: nil, isDuplicateLesson: false
                        ))
                        .background(dropFill("row-\(project.id)"), in: .rect(cornerRadius: ProjectLibrarySidebarLayout.rowRadius))
                        .projectDropTarget(.init(id: "row-\(project.id)", target: $dropTargetID) { ids in
                            vm.dropProjects(.init(ids: ids, destination: .folder(path: node.path, module: nil, before: nil)))
                        })
                    }
                } header: {
                    let title = prefix.isEmpty ? (node.modules.isEmpty ? "" : "Other recordings") : prefix
                    if !title.isEmpty {
                        BlitzUI.sectionLabel(title)
                            .contextMenu { ProjectFolderMenu(vm: vm, node: node) }
                    }
                }
            }
        }
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
            .padding(.horizontal, 6)
            .listRowInsets(ProjectLibrarySidebarLayout.rowInsets)
            .background(dropFill(request.id), in: .rect(cornerRadius: BlitzUI.controlRadius))
            .projectDropTarget(.init(id: request.id, target: $dropTargetID) { ids in
                vm.dropProjects(.init(ids: ids, destination: request.destination))
            })
    }

    private struct ModuleHeaderRequest {
        let node: ProjectFolderTree.Node
        let module: ProjectFolderTree.Module
        let prefix: String
    }

    private func moduleHeader(_ request: ModuleHeaderRequest) -> some View {
        let dropID = "module-\(request.node.id)-\(request.module.id)"
        let name = "Module \(ProjectLessonCode.number(request.module.id))"
        return HStack(spacing: 8) {
            BlitzUI.sectionLabel(request.prefix.isEmpty ? name : "\(request.prefix) › \(name)")
            if !request.module.duplicateLessonIDs.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.warning)
                    .help("Two recordings share a lesson number. Drag one to reorder and renumber this module.")
                    .accessibilityLabel("Duplicate lesson numbers")
            }
            Spacer(minLength: 4)
        }
        .frame(minHeight: 24)
        .background(dropFill(dropID), in: .rect(cornerRadius: BlitzUI.controlRadius))
        .contentShape(.rect)
        .projectDropTarget(.init(id: dropID, target: $dropTargetID) { ids in
            vm.dropProjects(.init(ids: ids, destination: .folder(path: request.node.path, module: request.module.id, before: nil)))
        })
        .contextMenu { ProjectModuleMenu(vm: vm, node: request.node, module: request.module) }
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

struct FolderRecordTargetChip: View {
    @Bindable var vm: RecorderViewModel

    var body: some View {
        if let target = vm.folderRecordTarget {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(BlitzType.symbol(12))
                    .foregroundStyle(BlitzUI.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(vm.recordTargetLabel(target))
                        .font(BlitzType.label)
                        .foregroundStyle(BlitzUI.primaryText)
                    if let detail = vm.recordTargetDetail(target) {
                        Text(detail)
                            .font(BlitzType.caption)
                            .foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
                Button {
                    vm.folderRecordTarget = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(BlitzType.symbol(10))
                        .frame(width: 18, height: 18)
                }
                .blitzButton(.quiet)
                .controlSize(.mini)
                .disabled(vm.countdownRemaining != nil || vm.state != .idle)
                .help("Save the next take to Recordings instead")
                .accessibilityLabel("Stop saving into \(target.path.name)")
            }
            .help("The next take is saved in this folder and named after it")
        }
    }
}
