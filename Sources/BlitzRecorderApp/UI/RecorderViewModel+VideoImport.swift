import AppKit
import UniformTypeIdentifiers

extension RecorderViewModel {
    static let importableVideoExtensions = ["mp4", "mov", "m4v"]

    var canImportVideos: Bool {
        libraryActions.videoImportProgress == nil && !projectTrash.isWorking
    }

    func chooseVideoToImport() {
        guard canImportVideos else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.importableVideoExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import"
        panel.message = "Edit and transcribe videos in their current location without copying them. Keep the original files available for playback and export."
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            _ = self.importVideos(panel.urls)
        }
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    /// Imports videos one after another, from the open panel or a Finder drop. Returns false when none can be imported.
    func importVideos(_ urls: [URL]) -> Bool {
        let videos = urls.filter { $0.isFileURL && Self.importableVideoExtensions.contains($0.pathExtension.lowercased()) }
        guard libraryActions.videoImportTask == nil, canImportVideos else { return false }
        guard !videos.isEmpty else {
            libraryActions.videoImportError = "Drop an MP4, MOV, or M4V video."
            return false
        }
        libraryActions.videoImportTask = Task {
            defer { libraryActions.videoImportTask = nil }
            var imported: [RecordingProjectHistory.Entry] = []
            for url in videos {
                guard !Task.isCancelled else { break }
                if let entry = await importVideo(url) { imported.append(entry) }
            }
            guard !imported.isEmpty else { return }
            projectLibraryNavigation.selectedProjectIDs = Set(imported.map(\.id))
            if videos.count == 1, studioMode == .projects, state == .idle, let entry = imported.first {
                openProject(entry)
            }
            let entries = await coordinator.projectLibrary.refresh(.init(settings: settings, includesLatestWrites: true))
            transcriptionController.syncProjects(entries)
        }
        return true
    }

    private func importVideo(_ url: URL) async -> RecordingProjectHistory.Entry? {
        libraryActions.videoImportError = nil
        libraryActions.videoImportProgress = .init(filename: url.lastPathComponent, stage: "Checking video", fraction: nil)
        defer { libraryActions.videoImportProgress = nil }
        let settings = settings
        let task = Task.detached(priority: .userInitiated) { [self] in
            try await VideoProjectImporter().importVideo(.init(url: url, settings: settings, onProgress: { progress in
                await MainActor.run { self.libraryActions.videoImportProgress = progress }
            }))
        }
        do {
            let project = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            let entry = RecordingProjectHistory.Entry(project)
            recentProjects.removeAll { $0.id == entry.id }
            recentProjects.insert(entry, at: 0)
            projectLibraryNavigation.section = .recordings
            projectLibraryNavigation.folderScope = nil
            projectLibraryNavigation.searchText = ""
            projectLibraryNavigation.selectedProjectIDs = [entry.id]
            transcriptionController.syncProjects(recentProjects)
            if project.sources.contains(where: { $0.role == "microphone" && $0.exists }) {
                transcriptionController.retry(.project(URL(fileURLWithPath: project.projectPath)))
            }
            return entry
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { libraryActions.videoImportError = error.localizedDescription }
        }
        return nil
    }
}
