import AppKit

/// Title writes run one at a time in the order they were asked for, so a move and its undo cannot swap.
private let projectTitleWriteQueue = DispatchQueue(label: "blitzrecorder.project-title-writes", qos: .userInitiated)

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
        folderIndex
    }

    func nextTakeTitle() -> String? {
        libraryActions.folderRecordTarget.map { target in
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
        libraryActions.folderRecordTarget = target
        showRecorder()
    }

    func titleKeepingFolder(_ request: ProjectTranscriptTitleRequest, generated: String) -> String {
        projectFolderIndex.resolved(request.project).with(generated).formatted
    }

    func moveProjects(_ request: ProjectFolderMoveRequest) {
        if let rename = request.folderRename {
            ProjectFolderStore.shared.rename(rename)
            if let target = libraryActions.folderRecordTarget, target.path.hasPrefix(rename.from) {
                libraryActions.folderRecordTarget = .init(path: target.path.replacingPrefix(rename), module: target.module)
            }
        }
        let previous = applyProjectTitles(request.titles)
        guard !previous.isEmpty || request.folderRename != nil else { return }
        libraryActions.folderMoveUndo = .init(message: request.message, previousTitles: previous,
                               folderRename: request.folderRename.map { .init(from: $0.to, to: $0.from) })
    }

    func undoFolderMove() {
        guard let undo = libraryActions.folderMoveUndo else { return }
        libraryActions.folderMoveUndo = nil
        if let rename = undo.folderRename { ProjectFolderStore.shared.rename(rename) }
        applyProjectTitles(undo.previousTitles)
    }

    /// Shows the new titles at once and writes them off the main thread, one library index write per library.
    /// Returns the titles they replace, for undo.
    @discardableResult
    func applyProjectTitles(_ titles: [UUID: String]) -> [UUID: String] {
        guard !titles.isEmpty, !projectTrash.isWorking else { return [:] }
        let changed = recentProjects.filter { titles[$0.id] != nil }
        guard !changed.isEmpty else { return [:] }
        let previous = Dictionary(changed.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(changed.map { ($0.projectPath, $0.displayTitle) }, uniquingKeysWith: { first, _ in first })
        let request = TakeFileStore.BatchRenameRequest(
            changes: changed.compactMap { entry in
                titles[entry.id].map { .init(projectURL: URL(fileURLWithPath: entry.projectPath), title: $0) }
            },
            settings: settings
        )
        recentProjects = recentProjects.map { entry in titles[entry.id].map(entry.retitled) ?? entry }
        let written = AsyncStream<TakeFileStore.BatchRenameOutcome> { continuation in
            projectTitleWriteQueue.async {
                continuation.yield(TakeFileStore().renameProjects(request))
                continuation.finish()
            }
        }
        Task {
            var iterator = written.makeAsyncIterator()
            guard let outcome = await iterator.next() else { return }
            if let open = lastExportedProject,
               let renamed = outcome.renamed.first(where: { $0.id == open.id }),
               renamed.editRevision == open.editRevision {
                lastExportedProject = renamed
            }
            await reloadRecentProjects()
            let failures = outcome.failures.map {
                "\(names[$0.projectURL.path] ?? $0.projectURL.deletingLastPathComponent().lastPathComponent): "
                    + $0.error.localizedDescription
            } + [outcome.indexError?.localizedDescription].compactMap { $0 }
            if !failures.isEmpty { projectLibraryError = failures.joined(separator: "\n") }
        }
        return previous
    }

    func exportFolder(_ projects: [RecordingProjectHistory.Entry]) {
        guard !projects.isEmpty, !isExporting, libraryActions.folderExportStatus == nil, state == .idle else { return }
        let service = MCPProjectService(coordinator: coordinator)
        let outputDirectory = settings.outputDirectory
        libraryActions.folderExportStatus = "Exporting 1 of \(projects.count)…"
        Task {
            var exported: [URL] = []
            var failures: [String] = []
            for (index, entry) in projects.enumerated() {
                libraryActions.folderExportStatus = "Exporting \(index + 1) of \(projects.count) · \(entry.displayTitle)"
                do {
                    let project = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: entry.projectPath))
                    let request = try service.makeExportRequest(.init(project: project, outputDirectory: outputDirectory))
                    exported.append(try await coordinator.exportProjectForAgent(request).url)
                } catch {
                    failures.append("\(entry.displayTitle): \(error.localizedDescription)")
                }
            }
            libraryActions.folderExportStatus = nil
            refreshRecentProjects()
            if !failures.isEmpty { projectLibraryError = "Some recordings did not export:\n" + failures.joined(separator: "\n") }
            if !exported.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(exported) }
        }
    }
}
