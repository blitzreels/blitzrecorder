import AppKit

struct ProjectFolderMoveUndo {
    let message: String
    let previousTitles: [UUID: String]
    let folderRename: ProjectFolderPath.PrefixReplacement?
}

struct ProjectFolderMoveRequest {
    let titles: [UUID: String]
    let message: String
    let folderRename: ProjectFolderPath.PrefixReplacement?
}

extension RecorderViewModel {
    var projectFolderIndex: ProjectFolderIndex {
        ProjectFolderIndex(.init(projects: recentProjects, pins: ProjectFolderStore.shared.pins))
    }

    func nextTakeTitle() -> String? {
        folderRecordTarget.map { target in
            ProjectFolderMoves.nextTitle(.init(target: target, index: projectFolderIndex, library: recentProjects)).formatted
        }
    }

    func recordTargetLabel(_ target: ProjectFolderRecordTarget) -> String {
        guard let module = target.module else { return target.path.displayPath }
        return "\(target.path.displayPath) › Module \(ProjectLessonCode.number(module))"
    }

    func recordTargetDetail(_ target: ProjectFolderRecordTarget) -> String? {
        let next = ProjectFolderMoves.nextTitle(.init(target: target, index: projectFolderIndex, library: recentProjects))
        guard let code = next.code else { return "Saved as \(target.path.title) - Title" }
        return "Next take: Lesson \(ProjectLessonCode.number(code.lesson))"
    }

    func recordInFolder(_ target: ProjectFolderRecordTarget) {
        if let module = target.module {
            ProjectFolderStore.shared.pinModule(.init(path: target.path, module: module))
        } else {
            ProjectFolderStore.shared.pin(target.path)
        }
        folderRecordTarget = target
        showRecorder()
    }

    func titleKeepingFolder(_ request: ProjectTranscriptTitleRequest, generated: String) -> String {
        projectFolderIndex.resolved(request.project).with(generated).formatted
    }

    func moveProjects(_ request: ProjectFolderMoveRequest) {
        if let rename = request.folderRename {
            ProjectFolderStore.shared.rename(rename)
            if let target = folderRecordTarget, target.path.hasPrefix(rename.from) {
                folderRecordTarget = .init(path: target.path.replacingPrefix(rename), module: target.module)
            }
        }
        let previous = applyProjectTitles(request.titles)
        guard !previous.isEmpty || request.folderRename != nil else { return }
        folderMoveUndo = .init(message: request.message, previousTitles: previous,
                               folderRename: request.folderRename.map { .init(from: $0.to, to: $0.from) })
    }

    func undoFolderMove() {
        guard let undo = folderMoveUndo else { return }
        folderMoveUndo = nil
        if let rename = undo.folderRename { ProjectFolderStore.shared.rename(rename) }
        applyProjectTitles(undo.previousTitles)
    }

    @discardableResult
    func applyProjectTitles(_ titles: [UUID: String]) -> [UUID: String] {
        guard !titles.isEmpty, !projectTrash.isWorking else { return [:] }
        let fileStore = TakeFileStore()
        var previous: [UUID: String] = [:]
        var failures: [String] = []
        for (id, title) in titles {
            guard let entry = recentProjects.first(where: { $0.id == id }) else { continue }
            do {
                let renamed = try fileStore.renameProject(.init(
                    projectURL: URL(fileURLWithPath: entry.projectPath), title: title, settings: settings
                ))
                previous[id] = entry.title
                if lastExportedProject?.id == renamed.id { lastExportedProject = renamed }
            } catch {
                failures.append("\(entry.displayTitle): \(error.localizedDescription)")
            }
        }
        refreshRecentProjects()
        if !failures.isEmpty { projectLibraryError = failures.joined(separator: "\n") }
        return previous
    }

    func exportFolder(_ projects: [RecordingProjectHistory.Entry]) {
        guard !projects.isEmpty, !isExporting, folderExportStatus == nil, state == .idle else { return }
        let service = MCPProjectService(coordinator: coordinator)
        let outputDirectory = settings.outputDirectory
        folderExportStatus = "Exporting 1 of \(projects.count)…"
        Task {
            var exported: [URL] = []
            var failures: [String] = []
            for (index, entry) in projects.enumerated() {
                folderExportStatus = "Exporting \(index + 1) of \(projects.count) · \(entry.displayTitle)"
                do {
                    let project = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: entry.projectPath))
                    let request = try service.makeExportRequest(.init(project: project, outputDirectory: outputDirectory))
                    exported.append(try await coordinator.exportProjectForAgent(request).url)
                } catch {
                    failures.append("\(entry.displayTitle): \(error.localizedDescription)")
                }
            }
            folderExportStatus = nil
            refreshRecentProjects()
            if !failures.isEmpty { projectLibraryError = "Some recordings did not export:\n" + failures.joined(separator: "\n") }
            if !exported.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(exported) }
        }
    }
}
