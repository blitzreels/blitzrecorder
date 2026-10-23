import AppKit
import Foundation

extension RecorderViewModel {
    func restoreStudioPage(_ saved: StudioPagePreference.Saved) {
        switch saved.page {
        case .record:
            studioMode = .record
        case .projects:
            studioMode = .projects
        case .edit:
            guard let entry = recentProjects.first(where: { $0.id == saved.projectID }) else {
                studioMode = .projects
                return
            }
            openProject(entry)
        }
    }

    var savedStudioPage: StudioPagePreference.Saved {
        StudioPagePreference.Saved(
            page: .init(studioMode),
            projectID: studioMode == .edit ? lastExportedProject?.id : nil
        )
    }

    func refreshProjectsInBackground() {
        guard projectRefreshTask == nil else { return }
        let settings = settings
        let library = coordinator.projectLibrary
        projectRefreshTask = Task { [weak self] in
            let entries = await library.refresh(.init(settings: settings, includesLatestWrites: false))
            guard let self, !Task.isCancelled else { return }
            self.projectRefreshTask = nil
            self.transcriptionController.syncProjects(entries)
        }
    }

    func refreshRecentProjects() {
        transcriptionController.syncProjects(coordinator.projectLibrary.reload(settings: settings))
    }

    /// After a save to one project: updates its row instead of reading every library again on the main thread.
    func refreshLibraryEntry(for project: RecordingProject) {
        if !coordinator.projectLibrary.replace(RecordingProjectHistory.Entry(project)) { refreshRecentProjects() }
    }

    func showRecorder() {
        if let onShowRecorder { onShowRecorder(); return }
        guard !projectTrash.isWorking else { return }
        studioMode = .record
    }

    func showProjects() {
        guard canShowProjects else { return }
        studioMode = .projects
        refreshProjectsInBackground()
    }

    /// Opens the library on the take that was just recorded, with search and folder cleared so it is visible.
    func showLastRecordingInLibrary() {
        guard let entry = currentEditorHistoryEntry else {
            showProjects()
            return
        }
        projectLibraryNavigation.section = .recordings
        projectLibraryNavigation.folderScope = nil
        projectLibraryNavigation.searchText = ""
        projectLibraryNavigation.filters = ProjectLibraryFilters()
        projectLibraryNavigation.selectedProjectIDs = [entry.id]
        showProjects()
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
            refreshLibraryEntry(for: renamedProject)
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
                title: titleKeepingFolder(request, generated: title)
            ))
        } catch {
            projectLibraryError = "Title generation failed: \(error.localizedDescription)"
        }
    }

    func fixProjectSpeakers(_ project: RecordingProjectHistory.Entry) async -> RecordingTranscript? {
        do {
            return try await transcriptionController.fixSpeakers(project)
        } catch {
            projectLibraryError = "Fixing speakers failed: \(error.localizedDescription)"
            return nil
        }
    }

    func renameTranscriptSpeaker(_ request: ProjectTranscriptSpeakerRenameRequest) async -> RecordingTranscript? {
        guard !transcriptionController.isUpdatingTranscript(request.project) else {
            projectLibraryError = LocalTranscriptionError.transcriptBusy.localizedDescription
            return nil
        }
        let projectURL = URL(fileURLWithPath: request.project.projectPath)
        let rename = request.rename
        do {
            try transcriptionController.beginSpeakerEdit(request.project)
            defer { transcriptionController.endSpeakerEdit(request.project) }
            let result = try await Task.detached(priority: .userInitiated) {
                let project = try TakeFileStore().loadRecordingProject(at: projectURL)
                let artifactStore = TranscriptArtifactStore()
                let locations = artifactStore.locations(for: project)
                let original = try artifactStore.load(from: locations.jsonURL)
                var transcript = original.renamingSpeaker(rename)
                if let index = transcript.speakers.firstIndex(where: { $0.id == rename.speakerID }) {
                    let speaker = original.speakers[index]
                    switch rename.voiceMemory {
                    case .unchanged:
                        if let id = rename.profileID {
                            transcript.speakers[index].savedVoiceID = id
                        } else if let suggestion = speaker.identitySuggestion, suggestion.name == rename.name {
                            transcript.speakers[index].savedVoiceID = suggestion.profileID
                        }
                    case .remember:
                        guard let voice = speaker.voice else {
                            throw SpeakerVoiceStore.VoiceMemoryError.insufficientSpeech
                        }
                        let id = try await SpeakerVoiceStore.shared.remember(.init(
                            name: rename.name, voice: voice,
                            profileID: speaker.savedVoiceID
                                ?? rename.profileID
                                ?? (speaker.identitySuggestion?.name == rename.name ? speaker.identitySuggestion?.profileID : nil)
                        ))
                        transcript.speakers[index].savedVoiceID = id
                    case .forget:
                        if let id = speaker.savedVoiceID { try await SpeakerVoiceStore.shared.forget(id) }
                        transcript.speakers[index].savedVoiceID = nil
                    }
                }
                try artifactStore.save(.init(transcript: transcript, locations: locations))
                if rename.voiceMemory == .remember,
                   let id = transcript.speakers.first(where: { $0.id == rename.speakerID })?.savedVoiceID,
                   let sample = try? await SpeakerSampleBuilder.shared.make(.init(
                       project: project, transcript: transcript, speakerID: rename.speakerID
                   )) {
                    defer { try? FileManager.default.removeItem(at: sample.url) }
                    try? await SpeakerVoiceStore.shared.savePreview(.init(profileID: id, sample: sample))
                }
                return (original, transcript, locations)
            }.value
            if let before = result.0.speakers.first(where: { $0.id == rename.speakerID }),
               let after = result.1.speakers.first(where: { $0.id == rename.speakerID }), before != after {
                TranscriptSpeakerUndo.shared.register(.init(
                    locations: result.2, before: before, after: after, manager: transcriptUndoManager,
                    isAvailable: { [weak self] in
                        self?.transcriptionController.isUpdatingTranscript(request.project) == false
                    },
                    onError: { [weak self] in self?.projectLibraryError = $0.localizedDescription }
                ))
                onEditorHistoryChanged?()
            }
            return result.1
        } catch {
            projectLibraryError = "Renaming the speaker failed: \(error.localizedDescription)"
            return nil
        }
    }

    var canOpenProjectEditor: Bool {
        !projectTrash.isWorking && (state == .idle || onRouteEditorProject != nil)
    }

    func openProject(_ project: RecordingProjectHistory.Entry) {
        guard !projectTrash.isWorking else { return }
        if coordinator.state != .idle, coordinator.lastTake?.projectURL.path == project.projectPath {
            detailMessage = "Finish recording this take before editing it."
            return
        }
        if onRouteEditorProject?(project) == true { return }
        guard state == .idle else { return }
        if lastExportedProject?.id == project.id {
            openEditor()
            return
        }
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
        guard !projectTrash.isWorking else { return }
        guard !projects.isEmpty else {
            projectLibraryError = "No recordings were selected. Select the recordings and try again."
            return
        }
        if let reason = projectTrashBlockingReason {
            projectLibraryError = reason
            return
        }
        guard !projects.contains(where: { $0.projectPath == exports.activeExportProjectURL?.path }) else {
            projectLibraryError = "Wait for this project's export to finish before moving its sources to Trash."
            return
        }
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

    var projectTrashBlockingReason: String? {
        switch coordinator.state == .idle ? state : coordinator.state {
        case .idle: nil
        case .starting: "A recording is starting. Stop it before moving or restoring projects."
        case .recording: "Stop the current recording before moving or restoring projects."
        case .paused: "The current recording is paused. Stop it before moving or restoring projects."
        case .finishing: "Wait for the current recording to finish saving, then try again."
        }
    }

    func restoreTrashedProjects() async {
        guard projectTrash.canRestore else { return }
        if let reason = projectTrashBlockingReason {
            projectLibraryError = reason
            return
        }
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
        guard !isExporting else { return }
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
            backgroundMusic: request.backgroundMusic,
            playbackRate: request.playbackRate
        ))
    }

    func exportOutputVariants(_ request: EditorVariantExportRequest) {
        guard let projectURL = lastExportedProjectURL, let project = lastExportedProject, state == .idle,
              !isExporting, !request.layouts.isEmpty else { return }
        exports.isExportingVariants = true
        exports.variantExportIndex = 0
        exports.variantExportTotal = request.layouts.count
        exports.variantExportURLs = []
        let outputDirectory = settings.outputDirectory
        let baseName = ProjectExportFilename.slug(from: project.title)
        Task {
            defer { exports.isExportingVariants = false }
            for layout in request.layouts {
                exports.variantExportIndex += 1
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
                        backgroundMusic: request.export.backgroundMusic, playbackRate: request.export.playbackRate
                    ))
                    exports.variantExportURLs.append(result.url)
                } catch { return }
            }
            request.onCompletion(exports.variantExportURLs)
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

    func openEditorWindow() {
        onOpenEditorWindow?(.init(
            project: hasSeparateEditorWindow ? nil : currentEditorHistoryEntry,
            presentsExport: false
        ))
    }

    var currentEditorHistoryEntry: RecordingProjectHistory.Entry? {
        guard let path = lastExportedProjectURL?.path else { return nil }
        return recentProjects.first { $0.projectPath == path }
    }

    func openEditor() {
        guard !projectTrash.isWorking else { return }
        if let project = currentEditorHistoryEntry, onRouteEditorProject?(project) == true { return }
        guard state == .idle else { return }
        if lastExportedProject == nil {
            clearEditorHistory()
            refreshLastExportedProject()
        }
        if lastExportedProject == nil {
            detailMessage = "This take's project file could not be opened."
        }
        studioMode = lastExportedProject != nil ? .edit : .record
    }

    func closeEditor() {
        studioMode = .record
    }

    func openEditorForExport() {
        if hasSeparateEditorWindow, let project = currentEditorHistoryEntry {
            onOpenEditorWindow?(.init(project: project, presentsExport: true))
            return
        }
        openEditor()
        guard studioMode == .edit else { return }
        exports.isEditorExportPresented = true
    }
}
