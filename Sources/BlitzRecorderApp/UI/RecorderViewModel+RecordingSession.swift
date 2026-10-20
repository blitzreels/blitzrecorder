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
        NotificationCenter.default.post(name: .livePreviewChanged, object: nil)
    }

    func applyExportProject(_ url: URL?) {
        exports.activeExportProjectURL = url
        if url != nil {
            exports.exportProgress = 0
            exports.lastExportError = nil
            exports.lastExportSucceededURL = nil
        }
    }

    func applyState(_ newState: RecordingState) {
        let previousState = state
        state = newState
        elapsedClock.applyState(newState, previousState: previousState)
        syncPreviewInteractionState()
        switch newState {
        case .starting:
            exports.isEditorExportPresented = false
            exports.renderProgress = 0
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
                exports.renderProgress = 0
            }
        case .paused:
            break
        case .finishing:
            if previousState != .finishing { session.finishingStartedAt = Date() }
            session.captureStopProgress = nil
            exports.renderProgress = 0
        case .idle:
            session.finishingStartedAt = nil
            session.captureStopProgress = nil
            exports.renderProgress = 0
        }
    }

    func applyMessage(_ message: String) {
        detailMessage = message
    }

    func applySavedRecordingOutput(_ output: SavedRecordingOutput) {
        if exports.activeExportProjectURL?.deletingLastPathComponent() == output.sourceDirectory {
            exports.lastExportError = nil
            exports.lastExportSucceededURL = output.url
            refreshProjectsInBackground()
            if lastExportedSourceTakeURL == output.sourceDirectory {
                lastExportedURL = output.url
                refreshLastExportedProject()
            }
            return
        }
        let keepsEditorOpen = studioMode == .edit
        exports.lastExportError = nil
        exports.lastExportSucceededURL = output.url
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
        exports.renderProgress = min(1, max(0, progress))
    }

    func applyExportFailure(_ message: String?) {
        exports.lastExportError = message
        if message != nil {
            exports.lastExportSucceededURL = nil
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
            canvas.isCameraCropModeEnabled = false
            canvas.isScreenCropModeEnabled = false
            previewStage.cancelCanvasInteraction()
            previewStage.sceneID = sceneID
            coordinator.endScreenCropEditing()
        }
        previewStage.sceneID = sceneID
        screenSource.targetWindowZoom = coordinator.settings.screenWindowZoom
        syncScreenCaptureAreaSelection()
        syncSelectedSource()
        syncPreviewInteractionState()
        previewStage.captureLayout = coordinator.settings.layout
        previewStage.sceneLayout = canvas.screenSplitPreviewHeight.map {
            SceneLayout.screenSplitLayout(screenHeight: CGFloat($0))
        } ?? sideSplitPreviewLayout ?? coordinator.settings.sceneLayout
        previewStage.enabledSources = coordinator.settings.visibleSources
        previewStage.fillsCanvasWhenOnlyVideoSource =
            coordinator.settings.enabledSources.intersection([.screen, .camera]).count == 1
        previewStage.applySettingsAspectRatio(coordinator.currentScreenSourceAspectRatio())
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
        previewStage.screenCornerRadius = coordinator.settings.screenCornerRadius
        previewStage.screenShadowEnabled = coordinator.settings.screenShadowEnabled
        previewStage.cameraCornerRadius = coordinator.settings.cameraCornerRadius
        previewStage.isBackgroundLayerSelected = isBackgroundLayerSelected
    }

    func refreshTargetWindow() {
        do {
            screenSource.targetWindowInfo = try coordinator.targetWindowInfo()
            screenSource.targetWindowStatus = ""
        } catch {
            screenSource.targetWindowInfo = nil
            screenSource.targetWindowStatus = error.localizedDescription
        }
    }

    func refreshSources() async {
        availableCameras = coordinator.availableCameras()
        availableMicrophones = coordinator.availableMicrophones()
        if state == .idle, settings.selectedMicrophoneName == nil, let id = settings.selectedMicrophoneID,
           availableMicrophones.contains(where: { $0.id == id }) {
            setMicrophone(id)
        }
        async let displays = coordinator.availableDisplays()
        async let screenSources = coordinator.availableScreenSources()
        availableDisplays = await displays
        availableScreenSources = await screenSources
        refreshScreenSourceAvailability()
    }

    func screenSourceThumbnail(_ binding: ScreenSourceBinding) async -> NSImage? {
        await coordinator.screenSourceThumbnail(binding)
    }

    func refreshRemoteCameraState() {
        settings = coordinator.settings
        availableCameras = coordinator.availableCameras()
        remoteCameraPreview.remoteCameraRefreshToken += 1
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
        canvas.screenSplitPreviewHeight
            ?? Double(settings.sceneLayout.screenSplitHeight ?? SceneSplitPolicy.inferredHeight(from: settings.sceneLayout) ?? SceneLayout.defaultScreenSplitHeight)
    }

    var activeScenePreset: ScenePreset? {
        showsScreenSplitControl ? .screenTop50 : settings.selectedScenePreset
    }

    var isCameraInsetLayout: Bool {
        SceneLayout.isCameraInsetFrame(settings.sceneLayout.cameraFrame)
    }

    var cameraFloats: Bool {
        settings.sceneLayout.cameraFloats(visibleSources: settings.visibleSources)
    }

    var cameraInsetAlignment: CameraInsetAlignment {
        SceneLayout.cameraInsetAlignment(for: settings.sceneLayout.cameraFrame)
    }

    var cameraInsetShape: CameraInsetShape {
        settings.sceneLayout.cameraInsetShape(in: settings.layout)
    }

    var cameraInsetSize: Double {
        Double(settings.sceneLayout.cameraInsetSize(in: settings.layout))
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
        canvas.screenSplitPreviewHeight = nil
        coordinator.setScreenSplitHeight(CGFloat(height))
        syncSettingsAfterSceneChange()
    }

    func previewScreenSplitHeight(_ height: Double) {
        guard canEditScene, showsScreenSplitControl else { return }
        let height = Double(SceneLayout.clampedScreenSplitHeight(CGFloat(height)))
        canvas.screenSplitPreviewHeight = height
        let layout = SceneLayout.screenSplitLayout(screenHeight: CGFloat(height))
        previewStage.sceneLayout = layout
        coordinator.previewSceneLayout(layout)
    }

    func commitScreenSplitPreview() {
        guard let height = canvas.screenSplitPreviewHeight else { return }
        guard canEditScene, showsScreenSplitControl else {
            cancelScreenSplitPreview()
            return
        }
        setScreenSplitHeight(height)
    }

    func cancelScreenSplitPreview() {
        guard canvas.screenSplitPreviewHeight != nil else { return }
        canvas.screenSplitPreviewHeight = nil
        previewStage.sceneLayout = coordinator.settings.sceneLayout
        coordinator.previewSceneLayout(coordinator.settings.sceneLayout)
    }

    var showsSideSplitControl: Bool {
        settings.layout != .vertical
            && settings.visibleSources.isSuperset(of: [.screen, .camera])
            && settings.sceneLayout.cameraSide != nil
    }

    var sideSplitCameraWidth: Double {
        canvas.sideSplitPreviewWidth ?? Double(settings.sceneLayout.sideBySideCameraWidth
            ?? SceneLayout.defaultSideBySideCameraWidth(for: settings.layout))
    }

    var sideSplitCameraIsLeft: Bool {
        settings.sceneLayout.cameraSide != .right
    }

    private var sideSplitPreviewLayout: SceneLayout? {
        guard let width = canvas.sideSplitPreviewWidth, let side = coordinator.settings.sceneLayout.cameraSide else { return nil }
        return SceneLayout.sideBySideLayout(.init(cameraWidth: CGFloat(width), cameraSide: side))
    }

    func setSideSplitCameraWidth(_ width: Double) {
        canvas.sideSplitPreviewWidth = nil
        guard let side = settings.sceneLayout.cameraSide else { return }
        coordinator.setSideBySideLayout(.init(cameraWidth: CGFloat(width), cameraSide: side))
        syncSettingsAfterSceneChange()
    }

    var sideSplitCameraSide: SceneCameraSide {
        settings.sceneLayout.cameraSide ?? .left
    }

    func setSideSplitCameraSide(_ side: SceneCameraSide) {
        cancelSideSplitPreview()
        coordinator.setSideBySideLayout(.init(cameraWidth: CGFloat(sideSplitCameraWidth), cameraSide: side))
        syncSettingsAfterSceneChange()
    }

    func previewSideSplitCameraWidth(_ width: Double) {
        guard canEditScene, showsSideSplitControl else { return }
        canvas.sideSplitPreviewWidth = Double(SceneLayout.clampedSideBySideCameraWidth(CGFloat(width)))
        guard let layout = sideSplitPreviewLayout else { return }
        previewStage.sceneLayout = layout
        coordinator.previewSceneLayout(layout)
    }

    func commitSideSplitPreview() {
        guard let width = canvas.sideSplitPreviewWidth else { return }
        guard canEditScene, showsSideSplitControl else {
            cancelSideSplitPreview()
            return
        }
        setSideSplitCameraWidth(width)
    }

    func cancelSideSplitPreview() {
        guard canvas.sideSplitPreviewWidth != nil else { return }
        canvas.sideSplitPreviewWidth = nil
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
            if session.countdownRemaining != nil {
                cancelCountdown()
            } else {
                requestRecordingStart()
            }
        case .recording, .paused:
            coordinator.stop()
        case .starting, .finishing:
            break
        }
    }

    func requestRecordingStart() {
        guard state == .idle, session.countdownRemaining == nil else { return }
        let readiness = coordinator.recordingReadiness()
        guard readiness.isReady else {
            resolveStartBlockers(readiness)
            return
        }
        if let missing = missingPreferredMicrophone {
            session.pendingMicrophoneFallback = missing
            return
        }
        beginCountdown()
    }

    /// Records this take with the current mic; the preferred one stays saved for the next take.
    func recordWithFallbackMicrophone() {
        session.pendingMicrophoneFallback = nil
        guard state == .idle, session.countdownRemaining == nil else { return }
        beginCountdown()
    }

    func setCountdownSeconds(_ seconds: Int) {
        RecordingCountdownPreference().setSeconds(seconds)
        session.countdownSeconds = RecordingCountdownPreference().seconds
    }

    func cancelCountdown() {
        session.countdownTask?.cancel()
        session.countdownTask = nil
        session.countdownRemaining = nil
    }

    private func beginCountdown() {
        guard state == .idle, session.countdownRemaining == nil, studioMode == .record else { return }
        session.countdownTask?.cancel()
        cancelScreenCropMode()
        if canvas.isCameraCropModeEnabled { cancelCameraCropMode() }
        guard session.countdownSeconds > 0 else {
            coordinator.start(takeTitle: nextTakeTitle())
            return
        }
        session.countdownRemaining = session.countdownSeconds
        session.countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: self.session.countdownSeconds, to: 0, by: -1) {
                self.session.countdownRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self.session.countdownTask = nil
            self.session.countdownRemaining = nil
            guard self.state == .idle, self.studioMode == .record,
                  self.coordinator.recordingReadiness().isReady else { return }
            self.coordinator.start(takeTitle: self.nextTakeTitle())
        }
    }

    func resolveStartBlockers(_ readiness: RecordingReadiness) {
        Task {
            if shouldUseScreenPickerForStart(readiness) {
                pickAndEnableScreenSource()
                detailMessage = "Choose a screen or window, then press Record."
                return
            }

            await coordinator.requestPermissionsForEnabledSources()
            syncSettings()

            let updatedReadiness = coordinator.recordingReadiness()
            if updatedReadiness.isReady {
                beginCountdown()
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

    var dockRecordingBlockerSummary: String? {
        _ = permissionRefreshToken
        let readiness = coordinator.recordingReadiness()
        guard !readiness.isReady,
              !readiness.blockers.contains(where: { sourceReadinessNotice($0.source) != nil }) else { return nil }
        return readiness.blockers.shortSummary
    }

    var recordingBlockerDetail: String? {
        let readiness = coordinator.recordingReadiness()
        return readiness.isReady ? nil : readiness.detail
    }

    var formattedElapsed: String {
        let total = session.elapsedSeconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var renderProgressLabel: String {
        "\(Int((exports.renderProgress * 100).rounded()))%"
    }

    var sessionProgressTitle: String {
        switch state {
        case .starting:
            return "Getting Ready"
        case .finishing:
            if remoteTransferProgress != nil {
                return "Downloading iPhone Media"
            }
            return session.captureStopProgress?.title ?? finishingMessageTitle ?? "Saving Recording"
        case .recording, .paused:
            return state == .paused ? "Paused" : "Recording"
        case .idle:
            return ""
        }
    }

    var sessionProgressValue: Double? {
        if state == .finishing, let remoteTransferProgress { return remoteTransferProgress.fraction }
        if let captureStopProgress = session.captureStopProgress { return captureStopProgress.fraction }
        if detailMessage.hasPrefix("Exporting") || detailMessage.hasPrefix("Removing camera background") {
            return exports.renderProgress
        }
        return nil
    }

    var sessionProgressLabel: String {
        if state == .finishing,
           let remoteTransferProgress {
            return "\(Int((remoteTransferProgress.fraction * 100).rounded()))%"
        }
        if let captureStopProgress = session.captureStopProgress { return captureStopProgress.label }
        return sessionProgressValue == nil ? "" : renderProgressLabel
    }

    var sessionProgressDetail: String? {
        if state == .starting {
            return sanitizedProgressMessage ?? "Not recording yet. Hang on while BlitzRecorder prepares capture."
        }
        guard state == .finishing else { return nil }
        if let remoteTransferProgress {
            return byteProgressLabel(remoteTransferProgress)
        }
        if let captureStopProgress = session.captureStopProgress { return captureStopProgress.detail }
        return "Your recording is being saved. Keep BlitzRecorder open."
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
