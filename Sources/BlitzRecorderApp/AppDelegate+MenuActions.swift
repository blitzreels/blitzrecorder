import AppKit

extension AppDelegate {
    @objc func showSettings() {
        windowController?.presentSettings()
    }

    @objc func showAbout() {
        AppSupportActions.showAboutPanel()
    }

    var canUndoEditor: Bool { windowController?.canUndoEditor ?? false }
    var canRedoEditor: Bool { windowController?.canRedoEditor ?? false }
    var editorUndoTitle: String { windowController?.editorUndoTitle ?? "Undo" }
    var editorRedoTitle: String { windowController?.editorRedoTitle ?? "Redo" }

    @objc func undoEditor() {
        windowController?.undoEditor()
    }

    @objc func redoEditor() {
        windowController?.redoEditor()
    }

    @objc func checkForUpdates() {
        updateController.checkForUpdates(nil)
    }

    var updateMenuItemTitle: String {
        updateController.actionTitle
    }

    var canCheckForUpdates: Bool {
        updateController.canCheckForUpdates
    }

    @objc func openReleaseNotes() {
        updateController.openReleaseNotes(nil)
    }

    @objc func openHelp() {
        AppSupportActions.openHelp()
    }

    @objc func reportIssue() {
        AppSupportActions.reportIssue(diagnostics: diagnosticsReport())
    }

    @objc func sendFeedback() {
        AppSupportActions.sendFeedback(diagnostics: diagnosticsReport())
    }

    @objc func copyDiagnostics() {
        AppSupportActions.copyDiagnostics(diagnosticsReport())
    }

    @objc func openPrivacyPolicy() {
        AppSupportActions.openPrivacyPolicy()
    }

    private func diagnosticsReport() -> String {
        AppDiagnostics.report(coordinator: coordinator, accessController: accessController)
    }

    @objc func startRecording() {
        guard let windowController else {
            coordinator.start()
            return
        }
        windowController.requestRecordingStart()
    }

    @objc func pauseRecording() {
        coordinator.pause()
    }

    @objc func resumeRecording() {
        coordinator.resume()
    }

    @objc func stopRecording() {
        coordinator.stop()
    }

    @objc func toggleRuleOfThirds() {
        coordinator.setRuleOfThirdsOverlayVisible(!coordinator.settings.showsRuleOfThirdsOverlay)
    }

    @objc func zoomIn() {
        coordinator.zoomIn()
    }

    @objc func zoomOut() {
        coordinator.zoomOut()
    }

    @objc func resetZoom() {
        coordinator.resetZoom()
    }

    @objc func chooseDisplayItem(_ sender: NSMenuItem) {
        coordinator.setDisplay(id: sender.representedObject as? String)
        mainMenuBuilder?.rebuild()
        windowController?.syncRuleOfThirdsOverlay()
    }

    @objc func chooseCameraItem(_ sender: NSMenuItem) {
        coordinator.setCamera(id: sender.representedObject as? String)
        mainMenuBuilder?.rebuild()
    }

    @objc func chooseMicrophoneItem(_ sender: NSMenuItem) {
        coordinator.setMicrophone(id: sender.representedObject as? String)
        mainMenuBuilder?.rebuild()
    }

    @objc func chooseLayoutItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layout = CaptureLayout(rawValue: raw) else { return }
        coordinator.setLayout(layout)
        mainMenuBuilder?.rebuild()
        windowController?.syncRuleOfThirdsOverlay()
    }

    @objc func fitFrontWindowForShorts() {
        coordinator.fitFrontWindowForShorts()
        mainMenuBuilder?.rebuild()
        windowController?.syncRuleOfThirdsOverlay()
    }

    @objc func makeTargetWindowWider() {
        coordinator.resizeTargetWindow(widthDelta: 48, heightDelta: 0)
    }

    @objc func makeTargetWindowNarrower() {
        coordinator.resizeTargetWindow(widthDelta: -48, heightDelta: 0)
    }

    @objc func makeTargetWindowTaller() {
        coordinator.resizeTargetWindow(widthDelta: 0, heightDelta: 48)
    }

    @objc func makeTargetWindowShorter() {
        coordinator.resizeTargetWindow(widthDelta: 0, heightDelta: -48)
    }

    @objc func pickScreen() {
        windowController?.showWindow(nil)
        windowController?.viewModel.pickScreen()
    }

    @objc func selectScreenRegion() {
        Task {
            do {
                try await coordinator.selectScreenCrop()
                mainMenuBuilder?.rebuild()
            } catch {
                coordinator.onMessage?("Screen region picker failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func clearScreenRegion() {
        coordinator.clearScreenCrop()
        mainMenuBuilder?.rebuild()
    }

    @objc func openOutputFolder() {
        NSWorkspace.shared.open(coordinator.settings.outputDirectory)
    }

    @objc func revealLastTake() {
        if let take = coordinator.lastTake {
            NSWorkspace.shared.activateFileViewerSelecting([take.finalVideoURL])
        } else {
            NSWorkspace.shared.open(coordinator.settings.outputDirectory)
        }
    }

    @objc func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = coordinator.settings.outputDirectory
        panel.prompt = "Choose"
        panel.message = "Choose where finished videos are saved. Source files and your library stay in place."
        if panel.runModal() == .OK, let url = panel.url {
            coordinator.setOutputDirectory(url)
            windowController?.syncRuleOfThirdsOverlay()
        }
    }

    @objc func mergeLastTake() {
        coordinator.mergeLastTake()
    }
}
