import AppKit
import UniformTypeIdentifiers

extension RecorderViewModel {
    func chooseVideoToImport() {
        guard videoImportProgress == nil, !projectTrash.isWorking else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mp4", "mov", "m4v"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import video"
        panel.message = "Edit and transcribe the video in its current location without copying it. Keep the original file available for playback and export."
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.videoImportTask = Task { await self.importVideo(url) }
        }
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    func importVideo(_ url: URL) async {
        guard videoImportProgress == nil, !projectTrash.isWorking else { return }
        videoImportError = nil
        videoImportProgress = .init(filename: url.lastPathComponent, stage: "Checking video", fraction: nil)
        defer {
            videoImportProgress = nil
            videoImportTask = nil
        }
        let settings = settings
        let task = Task.detached(priority: .userInitiated) { [self] in
            try await VideoProjectImporter().importVideo(.init(url: url, settings: settings, onProgress: { progress in
                await MainActor.run { self.videoImportProgress = progress }
            }))
        }
        do {
            let project = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            projectRefreshTask?.cancel()
            projectRefreshTask = nil
            let entries = await Task.detached(priority: .utility) {
                TakeFileStore().loadProjectHistory(settings: settings).entries
            }.value
            recentProjects = entries
            transcriptionController.syncProjects(entries)
            projectLibraryNavigation.section = .recordings
            projectLibraryNavigation.searchText = ""
            projectLibraryNavigation.selectedProjectIDs = [project.id]
            if project.sources.contains(where: { $0.role == "microphone" && $0.exists }) {
                transcriptionController.retry(.project(URL(fileURLWithPath: project.projectPath)))
            }
            if studioMode == .projects, state == .idle, let entry = entries.first(where: { $0.id == project.id }) {
                openProject(entry)
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { videoImportError = error.localizedDescription }
        }
    }
}
