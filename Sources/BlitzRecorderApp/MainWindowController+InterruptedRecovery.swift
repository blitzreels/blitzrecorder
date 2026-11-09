import AppKit

extension MainWindowController {
    func recoverInterruptedRecordings() {
        let settings = viewModel.settings
        Task { [weak self] in
            let outcomes = await Task.detached(priority: .utility) {
                await InterruptedTakeRecovery().recoverAll(.init(settings: settings))
            }.value
            guard !outcomes.isEmpty else { return }
            self?.present(outcomes)
        }
    }

    private func present(_ outcomes: [InterruptedTakeRecovery.Outcome]) {
        viewModel.refreshRecentProjects()
        var recovered: [RecordingProjectHistory.Entry] = []
        var messages: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .recovered(let entry, let notes):
                recovered.append(entry)
                viewModel.transcriptionController.enqueueProject(URL(fileURLWithPath: entry.projectPath))
                messages += notes
            case .failed(let takeDirectory, let reason):
                messages.append("A recording could not be recovered: \(reason) Its files are still in \(takeDirectory.path).")
            }
        }
        guard viewModel.state == .idle, let window else {
            viewModel.detailMessage = (["Recovered recording is in Projects."] + messages).joined(separator: " ")
            return
        }
        let alert = NSAlert()
        alert.messageText = recovered.isEmpty ? "Recording not recovered" : "Recovered recording"
        let lead = recovered.isEmpty ? "" : "BlitzRecorder closed during a recording. It is back in Projects."
        alert.informativeText = ([lead] + messages).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let canOpen = recovered.count == 1
        if canOpen { alert.addButton(withTitle: "Open Recording") }
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard canOpen, response == .alertFirstButtonReturn, let entry = recovered.first else { return }
            self?.openProject(entry)
        }
    }
}
