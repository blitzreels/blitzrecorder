import AppKit
import BlitzRecorderCore
import Foundation

extension RecorderViewModel {
    func generateAutomaticProjectTitle(
        _ completion: CompletedTranscription
    ) {
        guard case .project(let projectURL) = completion.source,
              automaticTitleTasks[projectURL.path] == nil else {
            return
        }
        automaticTitleTasks[projectURL.path] = Task { [weak self] in
            guard let self else { return }
            defer { automaticTitleTasks[projectURL.path] = nil }
            do {
                let fileStore = TakeFileStore()
                let project = try fileStore.loadRecordingProject(at: projectURL)
                let importedTitle = VideoProjectImporter.Metadata.load(for: project)?.initialTitle
                let folderPrefix = ProjectFolderTitle.untitledPrefix(project.title)
                guard transcriptionController.isAutomaticEnabled || importedTitle != nil,
                      folderPrefix != nil || RecordingProjectDisplayTitle.isUntitled(project.title)
                        || project.title == importedTitle
                else { return }
                let generatedTitle = try await TitleGenerator().title(
                    TitleGenerator.TranscriptTitleRequest(
                        transcript: completion.transcript.text
                    )
                )
                let title = (folderPrefix ?? "") + generatedTitle
                let currentProject = try fileStore.loadRecordingProject(at: projectURL)
                guard currentProject.title == project.title else { return }
                let renamedProject = try fileStore.renameProject(
                    RecordingProjectRenameRequest(
                        projectURL: projectURL,
                        title: title,
                        settings: settings
                    )
                )
                if lastExportedProject?.id == renamedProject.id {
                    lastExportedProject = renamedProject
                }
                refreshLibraryEntry(for: renamedProject)
                detailMessage = "Transcript ready · Renamed to \(title)"
            } catch {
                detailMessage = "Transcript ready · Automatic title skipped: \(error.localizedDescription)"
            }
        }
    }

    func revealLastSourceTracks() {
        guard let lastExportedSourceTakeURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastExportedSourceTakeURL])
    }

    func revealLastExportOrSource() {
        if let lastExportedURL, FileManager.default.fileExists(atPath: lastExportedURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lastExportedURL])
            return
        }
        revealLastSourceTracks()
    }

    func refreshLastExportedProject() {
        guard let projectURL = lastExportedProjectURL else {
            lastExportedProject = nil
            return
        }
        lastExportedProject = try? TakeFileStore().loadRecordingProject(at: projectURL)
    }

    var lastExportedProjectURL: URL? {
        lastExportedSourceTakeURL?.appendingPathComponent("project.blitzrecorder.json")
    }

    func retryRecoveredExport() {
        guard lastRecoveryOutput?.canRetryExport == true else {
            detailMessage = "This recovery needs the missing source media before export can be retried."
            return
        }
        coordinator.mergeLastTake()
    }

    func clearPostRecordingStatus() {
        resetLastRecordingOutputs()
        detailMessage = ""
    }

    func resetLastRecordingOutputs() {
        lastExportedURL = nil
        lastExportedSourceTakeURL = nil
        lastExportWarning = nil
        lastRecoveryOutput = nil
        lastPostRecordingProjectOutput = nil
        lastExportedProject = nil
        clearEditorHistory()
        studioMode = .record
    }

    func renameLastExportedFile() {
        guard let lastExportedURL else { return }
        let panel = NSSavePanel()
        panel.directoryURL = lastExportedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = lastExportedURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.prompt = "Rename"
        panel.message = "Choose a new name or folder for the finished recording."
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            guard destination.path != lastExportedURL.path else { return }
            do {
                let target = self.coordinator.uniqueOutputURL(destination)
                try FileManager.default.moveItem(at: lastExportedURL, to: target)
                self.lastExportedURL = target
                self.detailMessage = "Renamed: \(target.lastPathComponent)"
            } catch {
                self.detailMessage = "Rename failed: \(error.localizedDescription)"
            }
        }
    }
}
