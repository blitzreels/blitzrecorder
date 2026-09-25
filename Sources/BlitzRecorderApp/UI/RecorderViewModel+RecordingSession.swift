import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import QuartzCore

extension RecorderViewModel {
    func setLivePreviewEnabled(_ enabled: Bool) {
        guard state == .idle, isLivePreviewEnabled != enabled else { return }
        isLivePreviewEnabled = enabled
        LivePreviewPreference().setEnabled(enabled)
        if !enabled {
            micLevels.clear()
            sysLevels.clear()
        }
        onLivePreviewChanged?(enabled)
    }

    func applyState(_ newState: RecordingState) {
        let previousState = state
        state = newState
        elapsedClock.applyState(newState, previousState: previousState)
        syncPreviewInteractionState()
        switch newState {
        case .starting:
            renderProgress = 0
            detailMessage = RecordingStartCopy.preparing
            lastExportedURL = nil
            lastExportedSourceTakeURL = nil
            lastExportWarning = nil
            lastExportedProject = nil
            lastPostRecordingProjectOutput = nil
            clearEditorHistory()
            studioMode = .record
            lastRecoveryOutput = nil
        case .recording:
            if previousState == .idle || previousState == .starting || previousState == .finishing {
                renderProgress = 0
            }
        case .paused:
            break
        case .finishing:
            renderProgress = 0
        case .idle:
            renderProgress = 0
        }
    }

    func applyMessage(_ message: String) {
        detailMessage = message
    }

    func applySavedRecordingOutput(_ output: SavedRecordingOutput) {
        let keepsEditorOpen = studioMode == .edit
        lastExportError = nil
        lastExportSucceededURL = output.url
        lastExportedURL = output.url
        lastExportedSourceTakeURL = output.sourceDirectory
        lastExportWarning = output.warning
        lastRecoveryOutput = nil
        lastPostRecordingProjectOutput = nil
        refreshRecentProjects()
        refreshLastExportedProject()
        if !keepsEditorOpen {
            clearEditorHistory()
            studioMode = .record
        }
    }

    func applyPostRecordingProjectOutput(_ output: PostRecordingProjectOutput) {
        lastPostRecordingProjectOutput = output
        lastExportedURL = nil
        lastExportedSourceTakeURL = output.sourceDirectory
        lastExportWarning = output.warning
        lastRecoveryOutput = nil
        refreshRecentProjects()
        refreshLastExportedProject()
        transcriptionController.enqueueProject(output.projectURL)
        clearEditorHistory()
        studioMode = .record
    }

    func applyRecoveryOutput(_ output: RecordingRecoveryOutput) {
        lastRecoveryOutput = output
        lastExportedURL = nil
        lastExportedSourceTakeURL = nil
        lastExportWarning = nil
        lastPostRecordingProjectOutput = nil
        lastExportedProject = nil
        clearEditorHistory()
        studioMode = .record
        refreshRecentProjects()
    }

    func applyRenderProgress(_ progress: Double) {
        renderProgress = min(1, max(0, progress))
    }

    func applyExportFailure(_ message: String?) {
        lastExportError = message
        if message != nil {
            lastExportSucceededURL = nil
        }
    }

    func appendAudioLevel(_ level: Float, source: CaptureSource) {
        switch source {
        case .microphone: micLevels.append(level)
        case .systemAudio: sysLevels.append(level)
        case .screen, .camera: break
        }
    }

    func syncSettings() {
        settings = coordinator.settings
        let sceneID = coordinator.selectedSceneIDForCurrentLayout()
        if previewStage.sceneID != sceneID || previewStage.captureLayout != settings.layout {
            isCameraCropModeEnabled = false
            isScreenCropModeEnabled = false
            previewStage.cancelCanvasInteraction()
            previewStage.sceneID = sceneID
            coordinator.endScreenCropEditing()
        }
        previewStage.sceneID = sceneID
        targetWindowZoom = coordinator.settings.screenWindowZoom
        syncScreenCaptureAreaSelection()
        syncSelectedSource()
        syncPreviewInteractionState()
        previewStage.captureLayout = coordinator.settings.layout
        previewStage.sceneLayout = screenSplitPreviewHeight.map {
            SceneLayout.screenSplitLayout(screenHeight: CGFloat($0))
        } ?? coordinator.settings.sceneLayout
        previewStage.enabledSources = coordinator.settings.visibleSources
        previewStage.screenSourceAspectRatio = coordinator.currentScreenSourceAspectRatio()
        previewStage.screenFillsSceneFrame = ScreenSourceGeometry.fillsSceneFrame(for: coordinator.settings)
        previewStage.screenCrop = coordinator.settings.screenCrop
        previewStage.cameraCropAmount = coordinator.settings.cameraCropAmount
        previewStage.cameraCropPosition = coordinator.settings.cameraCropPosition
        previewStage.showsRuleOfThirdsOverlay = coordinator.settings.showsRuleOfThirdsOverlay
        previewStage.socialSafeZoneOverlay = coordinator.settings.socialSafeZoneOverlay
        previewStage.canvasBackgroundStyle = coordinator.settings.canvasBackgroundStyle
        previewStage.canvasBackgroundAnimated = coordinator.settings.canvasBackgroundAnimated
        previewStage.canvasPadding = coordinator.settings.canvasPadding
        previewStage.screenContentMode = coordinator.settings.screenContentMode
        previewStage.cameraContentMode = coordinator.settings.cameraContentMode
        previewStage.cameraFramePadding = coordinator.settings.cameraFramePadding
        previewStage.cameraShadowEnabled = coordinator.settings.cameraShadowEnabled
        previewStage.isBackgroundLayerSelected = isBackgroundLayerSelected
    }

    func refreshTargetWindow() {
        do {
            targetWindowInfo = try coordinator.targetWindowInfo()
            targetWindowStatus = ""
        } catch {
            targetWindowInfo = nil
            targetWindowStatus = error.localizedDescription
        }
    }

    func refreshSources() async {
        availableCameras = coordinator.availableCameras()
        availableMicrophones = coordinator.availableMicrophones()
        async let displays = coordinator.availableDisplays()
        async let screenSources = coordinator.availableScreenSources()
        availableDisplays = await displays
        availableScreenSources = await screenSources
    }

    func screenSourceThumbnail(_ binding: ScreenSourceBinding) async -> NSImage? {
        await coordinator.screenSourceThumbnail(binding)
    }

    func refreshRemoteCameraState() {
        settings = coordinator.settings
        availableCameras = coordinator.availableCameras()
        remoteCameraRefreshToken += 1
    }

    func startRemoteCameraDiscovery() {
        coordinator.startRemoteCameraDiscoveryIfNeeded()
        refreshRemoteCameraState()
    }

    func toggleSource(_ source: CaptureSource) {
        if source == .screen, !isSourceConfigured(.screen) {
            pickAndEnableScreenSource()
            return
        }
        if source == .systemAudio,
           !isSourceConfigured(.systemAudio),
           !coordinator.hasActiveScreenSourceSelection {
            pickAndEnableSystemAudioSource()
            return
        }

        if isSourceConfigured(source) {
            coordinator.removeSource(source)
        } else {
            coordinator.addSource(source)
        }
        syncSettings()
        if isSourceConfigured(source) {
            selectSource(source)
        }
    }

    func setSourceVisible(_ source: CaptureSource, visible: Bool) {
        if source == .screen,
           visible,
           (!isSourceConfigured(.screen) || !coordinator.hasActiveScreenSourceSelection) {
            pickAndEnableScreenSource()
            return
        }
        if source == .systemAudio,
           visible,
           !coordinator.hasActiveScreenSourceSelection {
            pickAndEnableSystemAudioSource()
            return
        }

        coordinator.setSource(source, enabled: visible)
        syncSettings()
    }

    func removeSource(_ source: CaptureSource) {
        coordinator.removeSource(source)
        syncSettings()
    }

    func isSourceConfigured(_ source: CaptureSource) -> Bool {
        settings.enabledSources.contains(source) || settings.hiddenSources.contains(source)
    }

    func isSourceVisible(_ source: CaptureSource) -> Bool {
        settings.visibleSources.contains(source)
    }

    var screenSplitHeight: Double {
        screenSplitPreviewHeight
            ?? Double(settings.sceneLayout.screenSplitHeight ?? SceneSplitPolicy.inferredHeight(from: settings.sceneLayout) ?? SceneLayout.defaultScreenSplitHeight)
    }

    var activeScenePreset: ScenePreset? {
        showsScreenSplitControl ? .screenTop50 : settings.selectedScenePreset
    }

    var isCameraInsetLayout: Bool {
        SceneLayout.isCameraInsetFrame(settings.sceneLayout.cameraFrame)
    }

    var cameraInsetAlignment: CameraInsetAlignment {
        SceneLayout.cameraInsetAlignment(for: settings.sceneLayout.cameraFrame)
    }

    var cameraInsetShape: CameraInsetShape {
        SceneLayout.cameraInsetShape(for: settings.sceneLayout.cameraFrame, in: settings.layout)
    }

    var cameraInsetSize: Double {
        Double(SceneLayout.cameraInsetSize(for: settings.sceneLayout.cameraFrame, in: settings.layout))
    }

    var cameraInsetSizeRange: ClosedRange<Double> {
        Double(SceneLayout.minimumCameraInsetSize)...Double(SceneLayout.maximumCameraInsetSize(for: settings.layout))
    }

    var showsScreenSplitControl: Bool {
        SceneSplitPolicy.showsControl(
            captureLayout: settings.layout,
            visibleSources: settings.visibleSources,
            sceneLayout: settings.sceneLayout,
            selectedPreset: settings.selectedScenePreset
        )
    }

    func isScenePresetActive(_ preset: ScenePreset) -> Bool {
        activeScenePreset == preset
    }

    func setScreenSplitHeight(_ height: Double) {
        screenSplitPreviewHeight = nil
        coordinator.setScreenSplitHeight(CGFloat(height))
        syncSettingsAfterSceneChange()
    }

    func previewScreenSplitHeight(_ height: Double) {
        guard canEditScene, showsScreenSplitControl else { return }
        let height = Double(SceneLayout.clampedScreenSplitHeight(CGFloat(height)))
        screenSplitPreviewHeight = height
        let layout = SceneLayout.screenSplitLayout(screenHeight: CGFloat(height))
        previewStage.sceneLayout = layout
        coordinator.previewSceneLayout(layout)
    }

    func commitScreenSplitPreview() {
        guard let height = screenSplitPreviewHeight else { return }
        guard canEditScene, showsScreenSplitControl else {
            cancelScreenSplitPreview()
            return
        }
        setScreenSplitHeight(height)
    }

    func cancelScreenSplitPreview() {
        guard screenSplitPreviewHeight != nil else { return }
        screenSplitPreviewHeight = nil
        previewStage.sceneLayout = coordinator.settings.sceneLayout
        coordinator.previewSceneLayout(coordinator.settings.sceneLayout)
    }

    func setCamera(_ id: String?) {
        coordinator.setCamera(id: id)
        syncSettings()
    }

    func setMicrophone(_ id: String?) {
        coordinator.setMicrophone(id: id)
        syncSettings()
    }

    func chooseOutputFolder() {
        guard state == .idle else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.outputDirectory
        panel.prompt = "Choose"
        panel.message = "Pick the folder where recordings will be saved."
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.state == .idle else { return }
            self.coordinator.setOutputDirectory(url)
            self.syncSettings()
            self.refreshRecentProjects()
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func generateAutomaticProjectTitle(
        _ completion: CompletedTranscription
    ) {
        guard transcriptionController.isAutomaticEnabled,
              case .project(let projectURL) = completion.source,
              automaticTitleTasks[projectURL.path] == nil else {
            return
        }
        automaticTitleTasks[projectURL.path] = Task { [weak self] in
            guard let self else { return }
            defer { automaticTitleTasks[projectURL.path] = nil }
            do {
                let fileStore = TakeFileStore()
                let project = try fileStore.loadRecordingProject(at: projectURL)
                guard RecordingProjectDisplayTitle.isUntitled(project.title) else { return }
                let title = try await TitleGenerator().title(
                    TitleGenerator.TranscriptTitleRequest(
                        transcript: completion.transcript.text
                    )
                )
                let currentProject = try fileStore.loadRecordingProject(at: projectURL)
                guard RecordingProjectDisplayTitle.isUntitled(currentProject.title) else { return }
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
                refreshRecentProjects()
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
        lastExportedURL = nil
        lastExportedSourceTakeURL = nil
        lastExportWarning = nil
        lastRecoveryOutput = nil
        lastPostRecordingProjectOutput = nil
        lastExportedProject = nil
        clearEditorHistory()
        studioMode = .record
        detailMessage = ""
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

    func primaryAction() {
        switch state {
        case .idle:
            let readiness = coordinator.recordingReadiness()
            guard readiness.isReady else {
                resolveStartBlockers(readiness)
                return
            }
            coordinator.start()
        case .recording, .paused:
            coordinator.stop()
        case .starting, .finishing:
            break
        }
    }

    func resolveStartBlockers(_ readiness: RecordingReadiness) {
        Task {
            if shouldUseScreenPickerForStart(readiness) {
                do {
                    try await coordinator.pickScreenSource()
                    syncSettings()
                    detailMessage = RecorderStudioLabels.screenSelectedForSession
                } catch {
                    detailMessage = RecorderStudioLabels.screenPickerFailed(error)
                    return
                }
            }

            await coordinator.requestPermissionsForEnabledSources()
            syncSettings()

            let updatedReadiness = coordinator.recordingReadiness()
            if updatedReadiness.isReady {
                coordinator.start()
            } else {
                detailMessage = updatedReadiness.blockers.first?.sentence ?? updatedReadiness.detail
            }
        }
    }

    func shouldUseScreenPickerForStart(_ readiness: RecordingReadiness) -> Bool {
        RecordingStartGate.shouldPickScreenForStart(readiness: readiness, settings: settings)
    }

    func togglePause() {
        switch state {
        case .recording:
            coordinator.pause()
        case .paused:
            coordinator.resume()
        default:
            break
        }
    }

    var canStartRecording: Bool {
        _ = permissionRefreshToken
        return coordinator.recordingReadiness().isReady
    }

    func openReadinessDetails() {
        onPresentSettings?(.permissions)
    }

    var recordingBlockerDetail: String? {
        let readiness = coordinator.recordingReadiness()
        return readiness.isReady ? nil : readiness.detail
    }

    var formattedElapsed: String {
        let total = elapsedSeconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var renderProgressLabel: String {
        "\(Int((renderProgress * 100).rounded()))%"
    }

    var sessionProgressTitle: String {
        switch state {
        case .starting:
            return "Getting Ready"
        case .finishing:
            if remoteTransferProgress != nil {
                return "Downloading iPhone Media"
            }
            return finishingMessageTitle ?? "Saving Recording"
        case .recording, .paused:
            return state == .paused ? "Paused" : "Recording"
        case .idle:
            return ""
        }
    }

    var sessionProgressValue: Double {
        if state == .finishing,
           let remoteTransferProgress {
            return remoteTransferProgress.fraction
        }
        return renderProgress
    }

    var sessionProgressLabel: String {
        if state == .finishing,
           let remoteTransferProgress {
            return "\(Int((remoteTransferProgress.fraction * 100).rounded()))%"
        }
        return renderProgressLabel
    }

    var sessionProgressDetail: String? {
        if state == .starting {
            return sanitizedProgressMessage ?? "Not recording yet. Hang on while BlitzRecorder prepares capture."
        }
        guard state == .finishing else { return nil }
        if let remoteTransferProgress {
            return byteProgressLabel(remoteTransferProgress)
        }
        return sanitizedProgressMessage
    }

    var sanitizedProgressMessage: String? {
        let message = detailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              !message.hasPrefix("Saved:"),
              !message.hasPrefix("Recording failed:") else {
            return nil
        }
        return message
    }

    var finishingMessageTitle: String? {
        guard let message = sanitizedProgressMessage else { return nil }
        if message.localizedCaseInsensitiveContains("download") ||
            message.localizedCaseInsensitiveContains("iphone") {
            return message
        }
        if message.hasSuffix("...") || message.hasSuffix("…") {
            return String(message.dropLast(message.hasSuffix("...") ? 3 : 1))
        }
        return message
    }

}
