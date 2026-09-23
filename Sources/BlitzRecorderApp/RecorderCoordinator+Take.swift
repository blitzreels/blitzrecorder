import os
import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
    func setSource(_ source: CaptureSource, enabled: Bool) {
        guard state == .idle || takeRecording.isUsingLiveCompositor else {
            onMessage?("Capture source visibility is locked while recording.")
            return
        }
        studio.setSourceVisibilityDuringLiveCompositor(source, enabled: enabled)
    }

    func uniqueOutputURL(_ url: URL) -> URL {
        takeFileStore.uniqueFileURL(url)
    }

    func setMicrophone(id: String?) {
        guard state == .recording || state == .paused else {
            studio.applyIdleMicrophone(id: id)
            return
        }
        guard settings.enabledSources.contains(.microphone) else {
            studio.applyIdleMicrophone(id: id)
            return
        }
        let device = id.flatMap { MicrophoneDeviceSelection.microphone(id: $0) }
            ?? MicrophoneDeviceSelection.fallbackMicrophone()
        guard let device else {
            onMessage?("Microphone unavailable. Recording continues with the current microphone.")
            return
        }
        Task {
            do {
                try await takeRecording.switchMicrophone(to: device.uniqueID)
                guard state == .recording || state == .paused else { return }
                settings.selectedMicrophoneID = id
                activeMicrophoneDeviceID = device.uniqueID
                persistSettings()
                onMessage?("Microphone switched to \(device.localizedName). Recording continues.")
            } catch {
                onMessage?(
                    "Could not switch microphone. Recording continues with the current microphone: "
                        + error.recorderFailureDescription
                )
            }
        }
    }

    func hasScreenCaptureAccess() -> Bool {
        permissionGate.hasScreenCaptureAccess
    }

    func recordingReadiness() -> RecordingReadiness {
        localCameraRuntimeState.applying(.init(
            readiness: RecordingStartGate.readiness(
                permission: permissionGate.readiness(for: settings),
                settings: settings,
                hasActiveScreenSourceSelection: hasActiveScreenSourceSelection,
                remoteBlocker: remoteCameraConnectionBlocker()
            ),
            settings: settings,
            isRemoteCameraSelected: isRemoteCameraSelected
        ))
    }

    func setLocalCameraRuntimeState(_ state: LocalCameraRuntimeState) {
        localCameraRuntimeState = state
    }

    func requestPermissionsForEnabledSources() async {
        let needsScreenRecordingGrant =
            (settings.enabledSources.contains(.screen)
                && !settings.usesPickedScreenContent)
            || settings.enabledSources.contains(.systemAudio)
        if needsScreenRecordingGrant {
            _ = await permissionGate.requestScreenCaptureAccess()
        }

        if settings.enabledSources.contains(.camera), !isRemoteCameraSelected {
            _ = await permissionGate.requestCameraAccess()
        }

        if settings.enabledSources.contains(.microphone) {
            _ = await permissionGate.requestMicrophoneAccess()
        }

    }

    func availableCameras() -> [SourceOption] {
        remoteCameraOptions() + CaptureDeviceCatalog.localCameraOptions()
    }

    func selectedCamera() -> AVCaptureDevice? {
        if isRemoteCameraSelected {
            return nil
        }
        if let selectedCameraID = settings.selectedCameraID,
           let device = AVCaptureDevice(uniqueID: selectedCameraID) {
            return device
        }

        return LocalCameraSessionConfiguration.selectedCamera(settings: settings)
    }

    func availableMicrophones() -> [SourceOption] {
        CaptureDeviceCatalog.microphoneOptions()
    }

    func selectedMicrophoneName() -> String {
        CaptureDeviceCatalog.microphoneName(selectedID: settings.selectedMicrophoneID)
    }

    func start() {
        guard state == .idle else { return }
        let readiness = recordingReadiness()
        guard readiness.isReady else {
            onMessage?(RecordingStartCopy.blockedMessage(enabledSourcesEmpty: settings.enabledSources.isEmpty))
            return
        }
        screenContentPicker.cancel()
        cancelPendingScreenWindowFits()
        do {
            let outputDirectoryAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
            guard recordingSession.beginPreparation(
                RecordingSession.PreparationRequest(outputDirectoryAccess: outputDirectoryAccess)
            ) else {
                outputDirectoryAccess.stop()
                return
            }
            activeCaptureWarnings = []
        } catch {
            onMessage?(RecordingStartCopy.failedMessage(for: error))
            return
        }
        onMessage?(RecordingStartCopy.preparing)

        Task {
            var createdTake: RecordingTake?
            var remoteStartCommandSent = false
            do {
                await prepareAudioLevelMonitoringForRecording()
                guard !settings.enabledSources.isEmpty else {
                    throw RecorderError.noSourcesSelected
                }
                await prepareScreenSourceWindowForRecording()
                let recordingSettingsForStart = RecordingStartSettings.effective(
                    settings,
                    hasScreenCaptureAccess: hasScreenCaptureAccess()
                )
                let recordingScreenFilter = try await resolvedScreenFilter(for: recordingSettingsForStart)
                let prepared = RecordingStartPrepared.make(
                    requestedSettings: settings,
                    recordingSettings: recordingSettingsForStart,
                    isRemoteCameraSelected: isRemoteCameraSelected,
                    pickedFilter: recordingScreenFilter
                )
                let recordingSettings = prepared.recordingSettings
                let initialRecordingScene = prepared.initialScene
                let skippedSystemAudio = prepared.skippedSystemAudio
                let startPlan = prepared.startPlan
                let access = prepared.access
                if access.remoteCamera {
                    try await requireRemoteCameraConnection()
                }
                if access.localCamera {
                    guard await permissionGate.requestCameraAccess() else {
                        throw RecorderError.noCamera
                    }
                    await cameraCutoutPreviewer.stop()
                }
                if access.microphone {
                    guard await permissionGate.requestMicrophoneAccess() else {
                        throw RecorderError.microphoneUnavailable
                    }
                }
                let take = try takeFileStore.createTake(settings: recordingSettings)
                createdTake = take
                recordingSession.noteActiveTake(
                    RecordingSessionActiveTake(take: take, settings: recordingSettings)
                )
                let remoteTakeID = prepared.remoteTakeID
                if let remoteTakeID {
                    remoteCamera.beginTake(
                        takeID: remoteTakeID,
                        take: take
                    )
                    remoteCamera.sendSettings()
                    _ = try await remoteCamera.prepare(
                        takeID: remoteTakeID,
                        hostStartTime: DispatchTime.now().uptimeNanoseconds
                    )
                }
                try RecordingStartGate.requireScreenCaptureAccess(
                    recordingSettings,
                    hasAccess: hasScreenCaptureAccess()
                )
                if startPlan.usesLiveCompositor {
                    if access.stopLocalCameraSession {
                        await cameraRecorder.stopSession()
                    }
                    if access.stopScreenPreview {
                        await stopScreenPreview()
                    }
                    let hostStartTime = try await takeRecording.startLiveCompositedTake(
                        take: take,
                        settings: recordingSettings,
                        initialScene: initialRecordingScene,
                        pickedScreenFilter: recordingScreenFilter,
                        prerollSeconds: 0
                    ) { [weak self] remaining in
                        self?.onMessage?(RecordingStartCopy.prerollMessage(remaining: remaining))
                    }
                    if let remoteTakeID {
                        remoteStartCommandSent = true
                        remoteCamera.markTimelineStart(takeID: remoteTakeID, hostTimelineStartTime: hostStartTime)
                        _ = try await remoteCamera.start(
                            takeID: remoteTakeID,
                            hostStartTime: hostStartTime,
                            hostTimelineStartTime: hostStartTime
                        )
                    }
                    commitStartedRecording(
                        recordingSettings: recordingSettings,
                        skippedSystemAudio: skippedSystemAudio,
                        usesLiveCompositor: true
                    )
                    return
                }
                try await takeRecording.startSourceFileTake(
                    take: take,
                    settings: startPlan.localCaptureSettings,
                    sceneTimelineSettings: startPlan.sceneTimelineSettings,
                    initialScene: initialRecordingScene,
                    pickedScreenFilter: recordingScreenFilter,
                    prerollSeconds: 0,
                    screenRecorder: screenRecorder,
                    cameraRecorder: cameraRecorder,
                    remoteCameraRecorder: startPlan.usesRemoteCamera ? remoteCamera : nil,
                    audioRecorder: audioRecorder,
                    systemAudioRecorder: systemAudioRecorder
                ) { [weak self] remaining in
                    self?.onMessage?(RecordingStartCopy.prerollMessage(remaining: remaining))
                }
                commitStartedRecording(
                    recordingSettings: recordingSettings,
                    skippedSystemAudio: skippedSystemAudio,
                    usesLiveCompositor: false
                )
            } catch {
                remoteCamera.cancelCommand()
                let cleanup = RecordingStartFailure.cleanup(
                    createdTake: createdTake != nil,
                    remoteStartCommandSent: remoteStartCommandSent,
                    hasRemoteTakeID: remoteCamera.activeTakeID != nil
                )
                if let activeRemoteCameraTakeID = remoteCamera.activeTakeID {
                    if cleanup.removePendingImport {
                        remoteCamera.removePendingImport(takeID: activeRemoteCameraTakeID)
                    }
                    if cleanup.abandonRemoteTake {
                        remoteCamera.abandonTake(takeID: activeRemoteCameraTakeID)
                    }
                }
                await takeRecording.stopAnyActiveRecording()
                if cleanup.cleanupTakeFiles, let createdTake {
                    takeFileStore.cleanupIntermediateFiles(for: createdTake, settings: settings)
                }
                recordingSession.failPreparation()
                committedRecordingSettings = nil
                clearActiveCaptureDevices()
                refreshAudioLevelMonitoring()
                onMessage?(RecordingStartCopy.failedMessage(for: error))
            }
        }
    }

    func prepareScreenSourceWindowForRecording() async {
        switch ScreenWindowFit.RecordingStartPlan.make(
            visibleScreen: settings.visibleSources.contains(.screen),
            hasAccessibility: permissionGate.hasAccessibilityAccess,
            usesPickedScreenContent: settings.usesPickedScreenContent,
            pickedKind: activePickedScreenContentKind,
            binding: settings.screenSourceBinding
        ) {
        case .picked:
            guard let filter = screenSourceSelection.pickedContentFilter else { return }
            let revision = beginScreenWindowFit()
            _ = await fitPickedScreenWindow(
                filter,
                zoom: settings.screenWindowZoom,
                shouldUpdateCapture: false,
                revision: revision
            )
        case .binding(let binding):
            let revision = beginScreenWindowFit()
            do {
                guard let arrangement = try await screenSourceWindowArrangement(
                    for: binding,
                    zoom: settings.screenWindowZoom,
                    revision: revision
                ) else {
                    return
                }
                applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: false)
            } catch {
                guard isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                onMessage?(RecordingStartCopy.windowFitSkipped(error))
            }
        case .skip:
            return
        }
    }

    func pause() {
        guard recordingSession.pause() else { return }
        takeRecording.pause()
    }

    func resume() {
        guard recordingSession.resume() else { return }
        takeRecording.resume()
    }

    func stop() {
        guard let stopContext = recordingSession.beginFinishing() else { return }
        let activeCaptureWarning = RecordingWarning.combined(activeCaptureWarnings.map(Optional.some))
        activeCaptureWarnings = []
        clearActiveCaptureDevices()
        screenContentPicker.cancel()
        cancelPendingScreenWindowFits()
        let pendingScreenPickerTransactionTask = screenReconfiguration.pickerTransactionTask
        let pendingScreenCaptureConfigurationTask = screenReconfiguration.configurationTask
        takeRecording.pauseSceneTimeline()
        onRenderProgress?(0)
        onMessage?(RecordingStartCopy.stopping)

        Task {
            do {
                await pendingScreenPickerTransactionTask?.value
                await pendingScreenCaptureConfigurationTask?.value
                let sceneEventsForFinalization = takeRecording.sceneEvents
                committedRecordingSettings = nil
                let takeToFinalize = stopContext.take
                let takeSettings = stopContext.settings ?? settings
                let stopOutcome = try await takeRecording.stop()
                switch stopOutcome {
                case .liveComposited(let completion, let warning):
                    onMessage?(RecordingStartCopy.saving)
                    onRenderProgress?(1)
                    let live = RecordingStopPresentation.liveComposited(
                        wroteMedia: completion.wroteMedia,
                        finalURL: completion.url,
                        take: takeToFinalize,
                        warning: RecordingWarning.combined([activeCaptureWarning, warning])
                    )
                    if RecordingStopPresentation.shouldCleanupTakeFiles(live), let takeToFinalize {
                        takeFileStore.cleanupIntermediateFiles(for: takeToFinalize, settings: takeSettings)
                    }
                    switch live {
                    case .saved(let savedOutput):
                        onSavedRecording?(savedOutput)
                        onMessage?(savedOutput.userMessage)
                    case .recovery(let recovery):
                        onRecordingRecovery?(recovery)
                        onMessage?(RecordingStopCopy.recovery(recovery.userMessage))
                    case .noFrames:
                        onMessage?(RecordingStopCopy.noFrames)
                    }
                    recordingSession.finish(with: nil)
                    refreshAudioLevelMonitoring()
                    return
                case .sourceFiles(let captureSummary):
                    if let takeToFinalize {
                        let outcome = await takeFinalizer.finalize(
                            take: takeToFinalize,
                            settings: takeSettings,
                            captureSummary: captureSummary,
                            sceneEvents: sceneEventsForFinalization
                        )
                        recordingSession.finish(with: outcome.retainedTake)
                        takeRecording.resetSceneTimeline()
                        refreshAudioLevelMonitoring()
                        presentFinalization(
                            RecordingStopPresentation.finalization(
                                outcome: outcome,
                                activeCaptureWarning: activeCaptureWarning,
                                savedRecordingStopWarning: captureSummary.savedRecordingStopWarning,
                                stopFailureWarning: captureSummary.stopFailureWarning,
                                settings: settings
                            )
                        )
                    } else {
                        recordingSession.finish(with: nil)
                        takeRecording.resetSceneTimeline()
                        refreshAudioLevelMonitoring()
                    }
                case .none:
                    recordingSession.finish(with: nil)
                    refreshAudioLevelMonitoring()
                }
            } catch {
                await takeRecording.stopAnyActiveRecording()
                recordingSession.finish(with: nil)
                takeRecording.resetSceneTimeline()
                onRenderProgress?(0)
                refreshAudioLevelMonitoring()
                onMessage?(RecordingStopCopy.stopFailed(error))
            }
        }
    }

    func presentFinalization(_ presentation: RecordingStopPresentation.Finalization) {
        switch presentation {
        case .project(let projectOutput):
            onPostRecordingProject?(projectOutput)
            onMessage?(projectOutput.userMessage)
        case .saved(let savedOutput):
            onSavedRecording?(savedOutput)
            onMessage?(savedOutput.userMessage)
        case .recovery(let recovery):
            onRecordingRecovery?(recovery)
            onMessage?(RecordingStopCopy.recovery(recovery.userMessage))
        case .message(let message):
            onMessage?(message)
        }
    }

    func commitStartedRecording(
        recordingSettings: RecordingSettings,
        skippedSystemAudio: Bool,
        usesLiveCompositor: Bool
    ) {
        recordingSession.markRecordingStarted()
        noteActiveCaptureDevices(settings: recordingSettings)
        committedRecordingSettings = settings
        onMessage?(RecordingStartCopy.recording(
            skippedSystemAudio: skippedSystemAudio,
            usesLiveCompositor: usesLiveCompositor
        ))
    }

    func handleActiveMicrophoneCaptureFailure(_ error: Error) {
        handleActiveCaptureFailure(ActiveCaptureFailure(source: .microphone, error: error))
    }

    func handleActiveCaptureFailure(_ failure: ActiveCaptureFailure) {
        guard state == .recording || state == .paused else { return }
        let recordingSettings = committedRecordingSettings ?? settings
        let decision = CaptureFailureRecovery.decision(.init(
            source: failure.source,
            enabledSources: recordingSettings.enabledSources,
            usesLiveCompositor: takeRecording.isUsingLiveCompositor,
            usesRemoteCamera: isRemoteCameraSelected
        ))
        if decision == .continueWithBlackCamera {
            cameraRecorder.continueWithBlackFrames()
            let warning = CaptureFailureRecovery.blackCameraWarning
            if !activeCaptureWarnings.contains(warning) {
                activeCaptureWarnings.append(warning)
            }
            onMessage?(warning)
            return
        }
        stop()
        onRequestForeground?()
        onMessage?(RecordingStopCopy.captureFailed(source: failure.source, error: failure.error))
    }

    func noteActiveCaptureDevices(settings: RecordingSettings) {
        activeMicrophoneDeviceID = ActiveCaptureDeviceIDs.microphone(settings: settings)
        activeLocalCameraDeviceID = ActiveCaptureDeviceIDs.localCamera(settings: settings)
    }

    func clearActiveCaptureDevices() {
        activeMicrophoneDeviceID = nil
        activeLocalCameraDeviceID = nil
    }

    func handleCaptureDeviceConnected(_ device: AVCaptureDevice) {
        let actions = CaptureDeviceEvent.connected(
            hasAudio: device.hasMediaType(.audio),
            hasVideo: device.hasMediaType(.video),
            isIdle: state == .idle
        )
        if actions.refreshAudio {
            refreshAudioLevelMonitoring()
        }
        if actions.notifyCamera {
            onCameraConfigurationChanged?()
        }
    }

    func handleCaptureDeviceDisconnected(_ device: AVCaptureDevice) {
        let actions = CaptureDeviceEvent.disconnected(
            isActiveMicrophone: device.hasMediaType(.audio) && activeMicrophoneDeviceID == device.uniqueID,
            isActiveLocalCamera: device.hasMediaType(.video) && activeLocalCameraDeviceID == device.uniqueID,
            isIdle: state == .idle
        )
        if actions.recoverMicrophone {
            recoverDisconnectedMicrophone(device)
        }
        if actions.failCamera {
            handleActiveCaptureFailure(ActiveCaptureFailure(
                source: .camera,
                error: RecorderError.mediaWriteFailed("The selected camera disconnected.")
            ))
        }
        if actions.refreshIdleAudio {
            refreshAudioLevelMonitoring()
        }
    }

    func recoverDisconnectedMicrophone(_ disconnectedDevice: AVCaptureDevice) {
        guard state == .recording || state == .paused else { return }
        guard let fallback = MicrophoneDeviceSelection.fallbackMicrophone(
            excluding: disconnectedDevice.uniqueID
        ) else {
            handleActiveCaptureFailure(ActiveCaptureFailure(
                source: .microphone,
                error: RecorderError.microphoneUnavailable
            ))
            return
        }
        Task {
            do {
                try await takeRecording.switchMicrophone(to: fallback.uniqueID)
                guard state == .recording || state == .paused else { return }
                activeMicrophoneDeviceID = fallback.uniqueID
                settings.selectedMicrophoneID = nil
                persistSettings()
                onMessage?(RecordingStopCopy.microphoneSwitched(fallback.localizedName))
            } catch {
                handleActiveCaptureFailure(ActiveCaptureFailure(source: .microphone, error: error))
            }
        }
    }

    func refreshAudioLevelMonitoring() {
        guard state == .idle, idleCaptureResourcesEnabled else { return }
        Task {
            await configureAudioLevelMonitoring()
        }
    }

    func mergeLastTake() {
        guard let lastTake else {
            onMessage?("No take to merge yet.")
            return
        }

        onExportFailure?(nil)
        Task {
            do {
                let outputAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
                defer { outputAccess.stop() }
                let url = try await Merger.exportFinalVideo(take: lastTake, settings: settings)
                let sourceDirectory = lastTake.scratchDirectory
                self.recordingSession.clearLastTake()
                let savedOutput = SavedRecordingOutput(url: url, sourceDirectory: sourceDirectory, warning: nil)
                onSavedRecording?(savedOutput)
                onMessage?(savedOutput.userMessage)
            } catch {
                exportLog.error("Final video export failed: \(error.recorderFailureDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
                onMessage?("Final video export failed: \(error.recorderFailureDescription)")
                onExportFailure?("Final video export failed. \(error.recorderFailureDescription)")
            }
        }
    }

    func exportProject(_ request: ProjectExportRequest) {
        Task {
            try? await exportProjectForAgent(request)
        }
    }

    func exportProjectForAgent(_ request: ProjectExportRequest) async throws -> SavedRecordingOutput {
        guard recordingSession.beginExport() else {
            let message = RecordingExportCopy.waitForRecording
            onMessage?(message)
            throw RecorderError.mediaWriteFailed(message)
        }

        onRenderProgress?(0)
        onExportFailure?(nil)
        onMessage?(RecordingExportCopy.exporting(request.outputFormat))

        defer {
            recordingSession.finishExport()
            refreshAudioLevelMonitoring()
        }

        do {
            let savedOutput = try await performProjectExport(request)
            onRenderProgress?(1)
            onSavedRecording?(savedOutput)
            onMessage?(savedOutput.userMessage)
            return savedOutput
        } catch {
            exportLog.error("Project export failed (destination \(request.destinationURL.path, privacy: .public)): \(error.recorderFailureDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
            onMessage?(RecordingExportCopy.failed(error))
            onExportFailure?(error.recorderFailureDescription)
            throw error
        }
    }

    func performProjectExport(_ request: ProjectExportRequest) async throws -> SavedRecordingOutput {
        var access = SecurityScopedResourceAccess(
            urls: [request.destinationURL, request.backgroundMusic?.url].compactMap { $0 }
        )
        access.start()
        defer { access.stop() }

        let project = try takeFileStore.loadRecordingProject(at: request.projectURL)
        let captureOutputFormat = ProjectExportRenderPlan.captureOutputFormat(
            project: project,
            fallback: settings.outputVideoFormat
        )
        let captureSettings = takeFileStore.recordingSettings(
            from: project,
            baseSettings: settings,
            outputFormat: captureOutputFormat
        )
        let exportSettings = takeFileStore.recordingSettings(
            from: project,
            baseSettings: settings,
            outputFormat: request.outputFormat
        )
        let outputAccess = try takeFileStore.prepareOutputDirectory(settings: exportSettings)
        defer { outputAccess.stop() }

        let take = takeFileStore.recordingTake(
            from: project,
            settings: exportSettings,
            outputFormat: request.outputFormat
        )
        let outputProject = project.outputProject(for: request.outputLayout ?? project.selectedOutputLayout)
        let context = ProjectExportRenderPlan.context(
            request: request,
            captureSettings: captureSettings,
            exportSettings: exportSettings,
            take: take,
            originalSceneEvents: takeFileStore.sceneEvents(from: project),
            outputProject: outputProject,
            outputSceneEvents: takeFileStore.sceneEvents(from: outputProject)
        )

        let url = try await Merger.exportFinalVideo(FinalVideoExportRequest(
            take: context.take,
            settings: context.renderSettings,
            sceneEvents: context.renderSceneEvents,
            backgroundMusic: request.backgroundMusic,
            destinationURL: request.destinationURL,
            progressHandler: { [weak self] progress in
                self?.onRenderProgress?(progress)
            },
            timelineEdits: outputProject.edits,
            playbackRate: request.playbackRate
        ))

        try takeFileStore.writeSourceTakeManifest(
            for: context.take,
            settings: context.captureSettings,
            finalVideoURL: url
        )
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let exportRecord = ProjectExportRenderPlan.exportRecord(
            url: url,
            request: request,
            renderSettings: context.renderSettings,
            fileSizeBytes: resourceValues?.fileSize.map(Int64.init)
        )
        try takeFileStore.writeRecordingProject(
            for: context.take,
            settings: context.captureSettings,
            sceneEvents: context.originalSceneEvents,
            finalVideoURL: url,
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: project.editorState,
            exportRecord: exportRecord
        )
        return ProjectExportRenderPlan.savedOutput(url: url, take: context.take)
    }

    func mutatingIdleProject<T>(_ body: () throws -> T) throws -> T {
        guard state == .idle else {
            throw RecorderError.mediaWriteFailed(
                "Wait for the current recording task to finish before editing the project."
            )
        }
        return try body()
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        correction: RecordingProjectSceneCorrection
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            let project = try takeFileStore.updateProjectSceneEvent(
                at: projectURL,
                eventIndex: eventIndex,
                correction: correction,
                baseSettings: settings
            )
            onMessage?("Updated project source segment.")
            return project
        }
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        mutate: (inout RecordingScene) -> Void
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.updateProjectScene(
                at: projectURL,
                eventIndex: eventIndex,
                baseSettings: settings,
                mutate: mutate
            )
        }
    }

    func insertProjectSceneEvent(at projectURL: URL, time: Double) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.insertProjectSceneEvent(
                at: projectURL,
                time: time,
                baseSettings: settings
            )
        }
    }

    func removeProjectSceneEvent(at projectURL: URL, eventIndex: Int) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.removeProjectSceneEvent(
                at: projectURL,
                eventIndex: eventIndex,
                baseSettings: settings
            )
        }
    }

    func restoreProjectSceneTimeline(
        _ request: RecordingProjectSceneRestoreRequest
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.restoreProjectSceneTimeline(request)
        }
    }

    func updateProjectEditorState(
        _ request: RecordingProjectEditorStateUpdateRequest
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.updateProjectEditorState(request)
        }
    }

    func zoomIn() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.zoomIn()
    }

    func zoomOut() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.zoomOut()
    }

    func resetZoom() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.resetZoom()
    }

    func openOutputFolder() {
        NSWorkspace.shared.open(settings.outputDirectory)
    }

    var shouldUseLiveCompositor: Bool {
        TakeRecordingRuntime.shouldUseLiveCompositor(
            settings: settings,
            isRemoteCameraSelected: isRemoteCameraSelected
        )
    }

    func localCaptureSettings(usesRemoteCamera: Bool) -> RecordingSettings {
        takeRecording.localCaptureSettings(settings, usesRemoteCamera: usesRemoteCamera)
    }

    func configureAudioLevelMonitoring() async {
        guard state != .idle || idleCaptureResourcesEnabled else {
            await stopAudioLevelMonitoring()
            return
        }
        if settings.enabledSources.contains(.microphone) {
            do {
                try microphoneLevelMonitor.start(settings: settings)
            } catch {
                microphoneLevelMonitor.stop()
            }
        } else {
            microphoneLevelMonitor.stop()
        }

        if settings.enabledSources.contains(.systemAudio) {
            let pickedScreenFilter = try? await resolvedScreenFilter(for: settings)
            guard pickedScreenFilter != nil else {
                try? await systemAudioLevelMonitor.stop()
                onAudioLevel?(.systemAudio, 0)
                return
            }
            guard state != .idle || idleCaptureResourcesEnabled else {
                await stopAudioLevelMonitoring()
                return
            }
            do {
                try await systemAudioLevelMonitor.start(.init(
                    settings: settings,
                    pickedScreenFilter: pickedScreenFilter
                ))
            } catch {
                try? await systemAudioLevelMonitor.stop()
            }
        } else {
            try? await systemAudioLevelMonitor.stop()
        }
        if state == .idle, !idleCaptureResourcesEnabled {
            await stopAudioLevelMonitoring()
        }
    }

    func stopAudioLevelMonitoring() async {
        microphoneLevelMonitor.stop()
        try? await systemAudioLevelMonitor.stop()
    }

    func prepareAudioLevelMonitoringForRecording() async {
        microphoneLevelMonitor.stop()
        guard settings.enabledSources.contains(.systemAudio) else {
            try? await systemAudioLevelMonitor.stop()
            return
        }
        do {
            if let stream = try systemAudioLevelMonitor.detachStreamForRecording() {
                systemAudioRecorder.adoptMonitoringStream(stream)
                return
            }
        } catch {
            try? await systemAudioLevelMonitor.stop()
        }
    }

    func startCaptureDeviceMonitoring() {
        captureDeviceMonitor.onConnected = { [weak self] device in
            self?.handleCaptureDeviceConnected(device)
        }
        captureDeviceMonitor.onDisconnected = { [weak self] device in
            self?.handleCaptureDeviceDisconnected(device)
        }
        captureDeviceMonitor.start()
    }

}
