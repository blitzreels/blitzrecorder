import os
import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
    func start(takeTitle: String?) {
        guard state == .idle else { return }
        windowFitLoopGuard.reset()
        screenFrameAspect.reset()
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
                let take = try takeFileStore.createTake(.init(settings: recordingSettings, date: Date(), title: takeTitle))
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
                takeRecording.onStopProgress = { [weak self] progress in
                    self?.onCaptureStopProgress?(progress)
                }
                let stopOutcome = try await takeRecording.stop()
                onCaptureStopProgress?(nil)
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
                onCaptureStopProgress?(nil)
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
}
