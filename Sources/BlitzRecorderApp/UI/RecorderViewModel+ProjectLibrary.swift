import AppKit
import Foundation

extension RecorderViewModel {
    func refreshRecentProjects() {
        recentProjects = TakeFileStore().loadProjectHistory(settings: settings).entries
        transcriptionController.syncProjects(recentProjects)
        if recentProjects.isEmpty, studioMode == .projects,
            projectTrash.status == nil, !projectTrash.canRestore, !projectTrash.isWorking {
            studioMode = .record
        }
    }

    func showRecorder() {
        guard !projectTrash.isWorking else { return }
        clearEditorHistory()
        studioMode = .record
    }

    func showProjects() {
        guard state == .idle else { return }
        clearEditorHistory()
        refreshRecentProjects()
        guard !recentProjects.isEmpty || projectTrash.canRestore else {
            studioMode = .record
            return
        }
        studioMode = .projects
    }

    func revealProject(_ project: RecordingProjectHistory.Entry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.takeDirectoryPath, isDirectory: true)])
    }

    func revealProjects(_ projects: [RecordingProjectHistory.Entry]) {
        NSWorkspace.shared.activateFileViewerSelecting(
            projects.map {
                URL(fileURLWithPath: $0.takeDirectoryPath, isDirectory: true)
            }
        )
    }

    func renameProject(
        _ request: ProjectLibraryRenameRequest
    ) {
        do {
            let renamedProject = try TakeFileStore().renameProject(
                RecordingProjectRenameRequest(
                    projectURL: URL(fileURLWithPath: request.project.projectPath),
                    title: request.title,
                    settings: settings
                )
            )
            if lastExportedProject?.id == renamedProject.id {
                lastExportedProject = renamedProject
            }
            refreshRecentProjects()
        } catch {
            projectLibraryError = error.localizedDescription
        }
    }

    func generateProjectTitle(
        _ request: ProjectTranscriptTitleRequest
    ) async {
        do {
            let title = try await TitleGenerator().title(
                TitleGenerator.TranscriptTitleRequest(
                    transcript: request.transcript
                )
            )
            renameProject(ProjectLibraryRenameRequest(
                project: request.project,
                title: title
            ))
        } catch {
            projectLibraryError = "Title generation failed: \(error.localizedDescription)"
        }
    }

    func openProject(_ project: RecordingProjectHistory.Entry) {
        guard !projectTrash.isWorking else { return }
        let projectURL = URL(fileURLWithPath: project.projectPath)
        let sourceDirectory = URL(fileURLWithPath: project.takeDirectoryPath, isDirectory: true)
        do {
            lastExportedProject = try TakeFileStore().loadRecordingProject(at: projectURL)
            lastPostRecordingProjectOutput = PostRecordingProjectOutput(
                projectURL: projectURL,
                sourceDirectory: sourceDirectory,
                warning: nil
            )
            lastExportedURL = project.finalVideoPath.map(URL.init(fileURLWithPath:))
            lastExportedSourceTakeURL = sourceDirectory
            lastExportWarning = nil
            lastRecoveryOutput = nil
            clearEditorHistory()
            studioMode = .edit
            onProjectOpened?()
        } catch {
            detailMessage = "Project could not be opened: \(error.localizedDescription)"
        }
    }

    func deleteProject(_ project: RecordingProjectHistory.Entry) async {
        await deleteProjects([project])
    }

    func deleteProjects(_ projects: [RecordingProjectHistory.Entry]) async {
        guard !projects.isEmpty, !projectTrash.isWorking, state == .idle else { return }
        projectLibraryError = nil
        let previousOrder = filteredLibraryProjects.map(\.id)
        let query = projectLibraryNavigation.searchText
        let outcome = await projectTrash.trash(.init(projects: projects, settings: settings))
        let deleted = projects.filter { outcome.completedIDs.contains($0.id) }
        if RecordingProjectLibrary.shouldClearOpenProject(
            deletedIDs: outcome.completedIDs,
            deletedTakePaths: Set(deleted.map(\.takeDirectoryPath)),
            openProjectID: lastExportedProject?.id,
            openTakePath: lastExportedSourceTakeURL?.path
        ) {
            lastExportedURL = nil
            lastExportedSourceTakeURL = nil
            lastExportWarning = nil
            lastRecoveryOutput = nil
            lastPostRecordingProjectOutput = nil
            lastExportedProject = nil
            clearEditorHistory()
        }
        refreshRecentProjects()
        if query == projectLibraryNavigation.searchText {
            projectLibraryNavigation.reconcileAfterRemoval(.init(
                previousOrder: previousOrder, removedIDs: outcome.completedIDs,
                availableIDs: filteredLibraryProjects.map(\.id)
            ))
        } else {
            projectLibraryNavigation.reconcileSelection(availableProjectIDs: filteredLibraryProjects.map(\.id))
        }
        studioMode = .projects
        reportProjectTrashFailures(outcome.failures)
    }

    func restoreTrashedProjects() async {
        guard projectTrash.canRestore, state == .idle else { return }
        projectLibraryError = nil
        let outcome = await projectTrash.restoreLastBatch()
        refreshRecentProjects()
        if !outcome.completedIDs.isEmpty {
            projectLibraryNavigation.searchText = ""
            projectLibraryNavigation.selectedProjectIDs = outcome.completedIDs
        }
        reportProjectTrashFailures(outcome.failures)
    }

    var filteredLibraryProjects: [RecordingProjectHistory.Entry] {
        RecordingProjectLibrary.matching(recentProjects, query: projectLibraryNavigation.searchText)
    }

    private func reportProjectTrashFailures(_ failures: [String]) {
        guard let message = RecordingProjectLibrary.trashFailureMessage(failures) else { return }
        projectLibraryError = message
    }

    func exportLastProject(_ request: EditorExportRequest) {
        guard let projectURL = lastExportedProjectURL, let project = lastExportedProject else {
            detailMessage = "No editable project is available for this recording."
            return
        }
        let baseName = ProjectExportFilename.slug(from: project.title)
        let destinationURL = coordinator.uniqueOutputURL(
            settings.outputDirectory
                .appendingPathComponent(baseName)
                .appendingPathExtension(request.outputFormat.fileExtension)
        )
        coordinator.exportProject(ProjectExportRequest(
            projectURL: projectURL,
            outputFormat: request.outputFormat,
            performanceProfile: request.performanceProfile,
            destinationURL: destinationURL,
            hiddenVideoSources: request.hiddenVideoSources,
            mutedAudioSources: request.mutedAudioSources,
            backgroundMusic: request.backgroundMusic
        ))
    }

    func exportOutputVariants(_ request: EditorVariantExportRequest) {
        guard let projectURL = lastExportedProjectURL, let project = lastExportedProject, state == .idle,
              !isExportingVariants, !request.layouts.isEmpty else { return }
        isExportingVariants = true
        variantExportIndex = 0
        variantExportTotal = request.layouts.count
        variantExportURLs = []
        let outputDirectory = settings.outputDirectory
        let baseName = ProjectExportFilename.slug(from: project.title)
        Task {
            defer { isExportingVariants = false }
            for layout in request.layouts {
                variantExportIndex += 1
                if Task.isCancelled { return }
                let suffix = ProjectExportFilename.variantSuffix(for: layout)
                let destination = coordinator.uniqueOutputURL(outputDirectory
                    .appendingPathComponent(baseName + "-" + suffix)
                    .appendingPathExtension(request.export.outputFormat.fileExtension))
                do {
                    let result = try await coordinator.exportProjectForAgent(.init(
                        outputLayout: layout, projectURL: projectURL, outputFormat: request.export.outputFormat,
                        performanceProfile: request.export.performanceProfile, destinationURL: destination,
                        hiddenVideoSources: request.export.hiddenVideoSources, mutedAudioSources: request.export.mutedAudioSources,
                        backgroundMusic: request.export.backgroundMusic
                    ))
                    variantExportURLs.append(result.url)
                } catch { return }
            }
        }
    }

    func exportLastProject(as format: OutputVideoFormat) {
        guard let project = lastExportedProject else {
            detailMessage = "No editable project is available for this recording."
            return
        }
        let resolution = OutputResolution(rawValue: project.settings.outputResolution) ?? .p1080
        let profile = ExportPerformanceProfile.resolved(
            preset: .balanced,
            sourceResolution: resolution,
            sourceFramesPerSecond: project.settings.framesPerSecond,
            customResolution: resolution,
            customFramesPerSecond: project.settings.framesPerSecond,
            customVideoQuality: .high
        )
        exportLastProject(EditorExportRequest(
            outputFormat: format,
            performanceProfile: profile,
            hiddenVideoSources: [],
            mutedAudioSources: [],
            backgroundMusic: nil
        ))
    }

    var lastRevealIsExport: Bool {
        guard let lastExportedURL else { return false }
        return FileManager.default.fileExists(atPath: lastExportedURL.path)
    }

    var canOpenEditor: Bool {
        lastExportedProject != nil || lastExportedProjectURL != nil
    }

    func openEditor() {
        clearEditorHistory()
        refreshLastExportedProject()
        if lastExportedProject == nil {
            detailMessage = "This take's project file could not be opened."
        }
        studioMode = lastExportedProject != nil ? .edit : .record
    }

    func closeEditor() {
        clearEditorHistory()
        studioMode = .record
    }
}
