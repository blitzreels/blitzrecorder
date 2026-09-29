import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
    func liveRecordingScene(for settings: RecordingSettings) -> RecordingScene {
        let screenFilter = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentFilter
            : nil
        return RecordingScene.live(settings: settings, pickedFilter: screenFilter)
    }

    func updateRecordingSceneIfNeeded(transition: RecordingSceneTransition = .cut) {
        let scene = liveRecordingScene(for: settings)
        takeRecording.updateScene(scene, transition: transition)
        if (state == .recording || state == .paused),
           settings.enabledSources.contains(.screen) {
            let pendingEvent = takeRecording.pendingSceneEvent(
                scene: scene,
                transition: transition
            )
            updateActiveScreenCaptureConfigurationIfNeeded(pendingEvent: pendingEvent)
        } else {
            takeRecording.appendSceneEventIfNeeded(scene, state: state, transition: transition)
            if state == .recording || state == .paused {
                committedRecordingSettings = settings
            }
        }
        synchronizeActiveCaptureSourcesIfNeeded()
    }

    func updateRecordingSceneTimeline(transition: RecordingSceneTransition) -> RecordingScene {
        let scene = liveRecordingScene(for: settings)
        takeRecording.updateScene(scene, transition: transition)
        takeRecording.appendSceneEventIfNeeded(scene, state: state, transition: transition)
        return scene
    }

    func updateActiveScreenCaptureConfigurationIfNeeded(
        pendingEvent: PendingRecordingSceneEvent
    ) {
        guard state == .recording || state == .paused,
              settings.enabledSources.contains(.screen) else {
            return
        }

        let requestedSettings = settings
        screenReconfiguration.configurationRevision += 1
        let generation = screenReconfiguration.configurationRevision
        let previousTask = screenReconfiguration.configurationTask
        let pickerTransactionTask = screenReconfiguration.pickerTransactionTask
        let pickerQueuedRevision: Int?
        if pickerTransactionTask == nil {
            pickerQueuedRevision = nil
        } else {
            screenReconfiguration.pickerQueuedRevision += 1
            pickerQueuedRevision = screenReconfiguration.pickerQueuedRevision
        }
        let task = Task {
            [
                weak self,
                previousTask,
                pickerTransactionTask,
                generation,
                pendingEvent,
                pickerQueuedRevision,
                requestedSettings
            ] in
            await pickerTransactionTask?.value
            await previousTask?.value
            guard let self,
                  self.shouldApplyActiveScreenCaptureConfiguration(generation: generation),
                  !ScreenCaptureGeometry.isStalePickerQueuedRevision(
                    pickerQueuedRevision,
                    current: self.screenReconfiguration.pickerQueuedRevision
                  ) else {
                return
            }
            let effectiveSettings = pickerTransactionTask == nil
                ? requestedSettings
                : self.settings
            let effectiveEvent: PendingRecordingSceneEvent
            if pickerTransactionTask == nil {
                effectiveEvent = pendingEvent
            } else {
                effectiveEvent = pendingEvent.resolving(scene: self.liveRecordingScene(for: effectiveSettings))
            }
            let captureSettings = self.localCaptureSettings(
                usesRemoteCamera: effectiveSettings.enabledSources.contains(.camera)
                    && self.isRemoteCameraSelected
            )
            do {
                let pickedScreenFilter = try await self.resolvedScreenFilter(for: captureSettings)
                try await self.takeRecording.updateScreenCapture(
                    settings: captureSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
                let resolvedScene = RecordingScene.live(
                    settings: effectiveSettings,
                    pickedFilter: pickedScreenFilter
                )
                self.takeRecording.appendPendingSceneEvent(
                    effectiveEvent.resolving(scene: resolvedScene),
                    state: self.state
                )
                self.committedRecordingSettings = effectiveSettings
            } catch {
                self.reportActiveScreenCaptureConfigurationFailure(error, generation: generation)
            }
        }
        screenReconfiguration.configurationTask = task
    }

    func cancelPendingActiveScreenCaptureConfigurationUpdate() {
        screenReconfiguration.configurationRevision += 1
        screenReconfiguration.configurationTask?.cancel()
        screenReconfiguration.configurationTask = nil
    }

    func shouldApplyActiveScreenCaptureConfiguration(generation: Int) -> Bool {
        !Task.isCancelled
            && screenReconfiguration.configurationRevision == generation
            && (state == .recording || state == .paused || state == .finishing)
    }

    func reportActiveScreenCaptureConfigurationFailure(_ error: Error, generation: Int) {
        if CaptureSourceRetargetFailure.shouldStopTake(for: error) {
            cancelPendingActiveScreenCaptureConfigurationUpdate()
            stop()
            onRequestForeground?()
            onMessage?(RecordingStopCopy.screenCaptureUpdateStoppedTake)
            return
        }
        guard screenReconfiguration.configurationRevision == generation else { return }
        cancelPendingActiveScreenCaptureConfigurationUpdate()
        if let committedRecordingSettings {
            settings = committedRecordingSettings
            persistSettings()
            if let committedScene = takeRecording.sceneEvents.last?.scene {
                takeRecording.updateScene(committedScene, transition: .cut)
            }
            onScreenCaptureConfigurationChanged?()
        }
        onMessage?("Screen capture update failed: \(error.recorderFailureDescription)")
    }

    func synchronizeActiveCaptureSourcesIfNeeded() {
        guard !takeRecording.isUsingLiveCompositor,
              state == .recording || state == .paused else {
            return
        }
        if settings.enabledSources.contains(.screen),
           !settings.usesPickedScreenContent,
           !hasScreenCaptureAccess() {
            onMessage?("Pick a screen or enable Screen Recording before adding screen capture to this recording.")
            return
        }
        let localSettings = currentLocalCaptureSettings()
        Task { [weak self, localSettings] in
            do {
                let pickedScreenFilter = try await self?.resolvedScreenFilter(for: localSettings)
                try await self?.takeRecording.startEnabledSources(
                    settings: localSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
            } catch {
                self?.onMessage?("Source could not be added to recording: \(error.localizedDescription)")
            }
        }
    }
}
