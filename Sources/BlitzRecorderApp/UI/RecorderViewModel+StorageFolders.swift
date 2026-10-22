import AppKit
import BlitzRecorderCore
import Foundation

extension RecorderViewModel {
    func chooseOutputFolder() {
        chooseOutputFolder { _ in }
    }

    func chooseOutputFolder(completion: @escaping (Bool) -> Void) {
        chooseStorageFolder(.init(kind: .exports, completion: completion))
    }

    func chooseSourceFolder() {
        chooseStorageFolder(.init(kind: .sources, completion: { _ in }))
    }

    private struct StorageFolderSelection {
        enum Kind { case exports, sources }
        let kind: Kind
        let completion: (Bool) -> Void
    }

    private func chooseStorageFolder(_ request: StorageFolderSelection) {
        guard state == .idle else { request.completion(false); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = request.kind == .sources ? settings.sourceStorage.url : settings.outputDirectory
        panel.title = request.kind == .sources ? "Choose source library folder" : "Choose export folder"
        panel.prompt = "Choose"
        panel.message = request.kind == .sources
            ? "New source tracks are saved in a BlitzRecorder Source Takes subfolder here. Existing projects stay available in their current folders."
            : "Choose where finished videos are saved. Source files and your library stay in place."
        let responseHandler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.state == .idle else {
                request.completion(false)
                return
            }
            switch request.kind {
            case .exports: self.coordinator.setOutputDirectory(url)
            case .sources: self.coordinator.setSourceDirectory(url)
            }
            self.syncSettings()
            self.refreshRecentProjects()
            request.completion(true)
        }
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: responseHandler)
        } else {
            panel.begin(completionHandler: responseHandler)
        }
    }
}
