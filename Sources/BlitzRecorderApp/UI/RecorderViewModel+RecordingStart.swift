import AppKit
import BlitzRecorderCore
import Foundation

extension RecorderViewModel {
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
}
