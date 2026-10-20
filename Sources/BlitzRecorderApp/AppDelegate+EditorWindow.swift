import AppKit

extension AppDelegate {
    @objc func showEditorWindow() {
        presentEditorWindow(.init(
            project: editorWindowController == nil ? windowController?.viewModel.currentEditorHistoryEntry : nil,
            presentsExport: false
        ))
    }

    @objc func showRecorderWindow() {
        windowController?.viewModel.showRecorder()
        presentMainWindow()
    }

    func presentEditorWindow(_ request: EditorWindowRequest) {
        guard let recorder = windowController?.viewModel else { return }
        if editorWindowController == nil {
            editorWindowController = EditorWindowController(.init(
                coordinator: coordinator,
                showRecorder: { [weak self] in self?.showRecorderWindow() },
                showSettings: { [weak self] pane in self?.windowController?.presentSettings(selecting: pane) },
                historyChanged: { [weak self] in self?.mainMenuBuilder?.rebuild() },
                closed: { [weak self] in
                    self?.editorWindowController?.viewModel.stopObservingProjectEdits()
                    self?.editorWindowController = nil
                    guard let recorder = self?.windowController?.viewModel else { return }
                    recorder.hasSeparateEditorWindow = false
                    recorder.refreshLastExportedProject()
                    recorder.clearEditorHistory()
                    recorder.refreshProjectsInBackground()
                    self?.mainMenuBuilder?.rebuild()
                }
            ))
        }
        guard let editorWindowController else { return }
        let transfersHistory = !recorder.hasSeparateEditorWindow
            && recorder.lastExportedProject?.id == request.project?.id
        recorder.hasSeparateEditorWindow = true
        if recorder.studioMode == .edit { recorder.showRecorder() }
        editorWindowController.present(request)
        if transfersHistory {
            recorder.moveEditorHistory(to: editorWindowController.viewModel)
        }
    }
}
