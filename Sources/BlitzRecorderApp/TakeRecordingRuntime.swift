import Foundation
import ScreenCaptureKit

@MainActor
final class TakeRecordingRuntime {
    private enum Mode {
        case idle
        case liveCompositor
        case captureRun(CaptureSourceRun)
    }

    let liveCompositedRecorder: LiveCompositedRecorder

    private var mode: Mode = .idle
    private(set) var sceneEvents: [RecordingSceneEvent] = []
    private var timelineSegmentStartedAt: Date?
    private var timelineAccumulatedSeconds: TimeInterval = 0

    init(liveCompositedRecorder: LiveCompositedRecorder = LiveCompositedRecorder()) {
        self.liveCompositedRecorder = liveCompositedRecorder
    }

    var isUsingLiveCompositor: Bool {
        if case .liveCompositor = mode { return true }
        return false
    }

    var activeCaptureRun: CaptureSourceRun? {
        if case .captureRun(let captureRun) = mode { return captureRun }
        return nil
    }

    func markLiveCompositorStarted() {
        mode = .liveCompositor
    }

    func setActiveCaptureRun(_ captureRun: CaptureSourceRun) {
        mode = .captureRun(captureRun)
    }

    func pause() {
        pauseSceneTimeline()
        switch mode {
        case .liveCompositor:
            liveCompositedRecorder.pause()
        case .captureRun(let captureRun):
            captureRun.pause()
        case .idle:
            break
        }
    }

    func resume() {
        resumeSceneTimeline()
        switch mode {
        case .liveCompositor:
            liveCompositedRecorder.resume()
        case .captureRun(let captureRun):
            captureRun.resume()
        case .idle:
            break
        }
    }

    func stopLiveCompositor() async throws -> MediaWriterCompletion {
        defer {
            mode = .idle
            resetSceneTimeline()
        }
        return try await liveCompositedRecorder.stop()
    }

    func stopCaptureRun() async -> CaptureSourceRunSummary {
        guard case .captureRun(let captureRun) = mode else {
            return CaptureSourceRunSummary(completions: [:])
        }
        mode = .idle
        return await captureRun.stop()
    }

    func stopAnyActiveRecording() async {
        switch mode {
        case .liveCompositor:
            _ = try? await liveCompositedRecorder.stop()
        case .captureRun(let captureRun):
            _ = await captureRun.stop()
        case .idle:
            break
        }
        mode = .idle
        resetSceneTimeline()
    }

    func reset() {
        mode = .idle
        resetSceneTimeline()
    }

    func updateScene(_ scene: RecordingScene) {
        if isUsingLiveCompositor {
            liveCompositedRecorder.updateScene(scene)
        }
    }

    func startSceneTimeline(settings: RecordingSettings) {
        timelineAccumulatedSeconds = 0
        timelineSegmentStartedAt = Date()
        sceneEvents = [
            RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings))
        ]
    }

    func pauseSceneTimeline() {
        guard let timelineSegmentStartedAt else { return }
        timelineAccumulatedSeconds += Date().timeIntervalSince(timelineSegmentStartedAt)
        self.timelineSegmentStartedAt = nil
    }

    func resumeSceneTimeline() {
        guard timelineSegmentStartedAt == nil else { return }
        timelineSegmentStartedAt = Date()
    }

    func resetSceneTimeline() {
        sceneEvents = []
        timelineSegmentStartedAt = nil
        timelineAccumulatedSeconds = 0
    }

    func appendSceneEventIfNeeded(_ scene: RecordingScene, state: RecordingState) {
        guard state == .recording || state == .paused else { return }
        if sceneEvents.last?.scene == scene { return }

        let eventTime = currentSceneTime()
        let event = RecordingSceneEvent(time: eventTime, scene: scene)
        if let last = sceneEvents.last,
           abs(last.time - eventTime) < 0.05 {
            sceneEvents[sceneEvents.count - 1] = event
        } else {
            sceneEvents.append(event)
        }
    }

    func localCaptureSettings(_ settings: RecordingSettings, usesRemoteCamera: Bool) -> RecordingSettings {
        guard usesRemoteCamera else { return settings }
        var localSettings = settings
        localSettings.enabledSources.remove(.camera)
        return localSettings
    }

    static func shouldUseLiveCompositor(settings: RecordingSettings, isRemoteCameraSelected: Bool) -> Bool {
        !settings.savesSourceFiles
            && !settings.removesCameraBackgroundAfterRecording
            && !isRemoteCameraSelected
    }

    private func currentSceneTime() -> TimeInterval {
        guard let timelineSegmentStartedAt else {
            return timelineAccumulatedSeconds
        }
        return timelineAccumulatedSeconds + Date().timeIntervalSince(timelineSegmentStartedAt)
    }
}
