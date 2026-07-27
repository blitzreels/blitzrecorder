import Foundation
import CoreMedia
import ScreenCaptureKit

enum TakeRecordingStopOutcome {
    case liveComposited(MediaWriterCompletion, warning: String?)
    case sourceFiles(CaptureSourceRunSummary)
    case none
}

struct PendingRecordingSceneEvent {
    let time: TimeInterval
    let scene: RecordingScene
    let transition: RecordingSceneTransition

    func resolving(scene: RecordingScene) -> PendingRecordingSceneEvent {
        PendingRecordingSceneEvent(time: time, scene: scene, transition: transition)
    }
}

@MainActor
protocol LiveCompositedRecording: AnyObject {
    var onCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)? { get set }
    var onScreenPreviewFrame: ScreenPreviewer.FrameHandler? { get set }
    var activeScreenCaptureStream: SCStream? { get }

    func start(
        take: RecordingTake,
        settings: RecordingSettings,
        filter pickedFilter: SCContentFilter?,
        prerollSeconds: Int,
        prerollHandler: (@MainActor (Int) -> Void)?
    ) async throws
    func pause()
    func resume()
    func stop() async throws -> MediaWriterCompletion
    func updateScene(_ scene: RecordingScene, transition: RecordingSceneTransition)
    func updateScreenCapture(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws
}

extension LiveCompositedRecording {
    var activeScreenCaptureStream: SCStream? { nil }
}

@MainActor
final class TakeRecordingRuntime {
    private enum Mode {
        case idle
        case liveCompositor
        case captureRun(CaptureSourceRun)
    }

    private let liveCompositedRecorder: LiveCompositedRecording

    private var mode: Mode = .idle
    private(set) var sceneEvents: [RecordingSceneEvent] = []
    private var timelineSegmentStartedAt: Date?
    private var timelineAccumulatedSeconds: TimeInterval = 0

    init(liveCompositedRecorder: LiveCompositedRecording = LiveCompositedRecorder()) {
        self.liveCompositedRecorder = liveCompositedRecorder
    }

    var isUsingLiveCompositor: Bool {
        if case .liveCompositor = mode { return true }
        return false
    }

    var activeScreenCaptureStream: SCStream? {
        switch mode {
        case .liveCompositor:
            liveCompositedRecorder.activeScreenCaptureStream
        case .captureRun(let captureRun):
            captureRun.activeScreenCaptureStream
        case .idle:
            nil
        }
    }

    func setLiveCompositorCameraPreviewHandler(_ handler: @escaping (CMSampleBuffer, Int, Int) -> Void) {
        liveCompositedRecorder.onCameraPreviewSampleBuffer = handler
    }

    func setLiveCompositorScreenPreviewHandler(_ handler: @escaping ScreenPreviewer.FrameHandler) {
        liveCompositedRecorder.onScreenPreviewFrame = handler
    }

    @discardableResult
    func startLiveCompositedTake(
        take: RecordingTake,
        settings: RecordingSettings,
        initialScene: RecordingScene,
        pickedScreenFilter: SCContentFilter?,
        prerollSeconds: Int,
        prerollHandler: ((Int) -> Void)?
    ) async throws -> UInt64 {
        try await liveCompositedRecorder.start(
            take: take,
            settings: settings,
            filter: pickedScreenFilter,
            prerollSeconds: prerollSeconds,
            prerollHandler: prerollHandler
        )
        mode = .liveCompositor
        startSceneTimeline(scene: initialScene)
        return DispatchTime.now().uptimeNanoseconds
    }

    @discardableResult
    func startSourceFileTake(
        take: RecordingTake,
        settings: RecordingSettings,
        sceneTimelineSettings: RecordingSettings? = nil,
        initialScene: RecordingScene,
        pickedScreenFilter: SCContentFilter?,
        prerollSeconds: Int,
        screenRecorder: ScreenCaptureRecording,
        cameraRecorder: CameraCaptureRecording,
        remoteCameraRecorder: RemoteCameraCaptureRecording? = nil,
        audioRecorder: MicrophoneCaptureRecording,
        systemAudioRecorder: SystemAudioCaptureRecording,
        prerollHandler: ((Int) -> Void)?
    ) async throws -> CaptureSourceRunStartResult {
        let captureRunSettings = remoteCameraRecorder == nil
            ? settings
            : (sceneTimelineSettings ?? settings)
        let captureRun = CaptureSourceRun(
            take: take,
            settings: captureRunSettings,
            pickedScreenFilter: pickedScreenFilter,
            screenRecorder: screenRecorder,
            cameraRecorder: cameraRecorder,
            remoteCameraRecorder: remoteCameraRecorder,
            audioRecorder: audioRecorder,
            systemAudioRecorder: systemAudioRecorder
        )
        mode = .captureRun(captureRun)
        let start = try await captureRun.start(
            prerollSeconds: prerollSeconds,
            prerollHandler: prerollHandler
        )
        startSceneTimeline(scene: initialScene)
        return start
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

    func stop() async throws -> TakeRecordingStopOutcome {
        pauseSceneTimeline()
        switch mode {
        case .liveCompositor:
            let (completion, warning) = try await stopLiveCompositor()
            return .liveComposited(completion, warning: warning)
        case .captureRun:
            let summary = await stopCaptureRun()
            return .sourceFiles(summary)
        case .idle:
            resetSceneTimeline()
            return .none
        }
    }

    private func stopLiveCompositor() async throws -> (MediaWriterCompletion, warning: String?) {
        defer {
            mode = .idle
            resetSceneTimeline()
        }
        do {
            return (try await liveCompositedRecorder.stop(), nil)
        } catch let stopFailure as CaptureSourceStopFailure {
            return (
                stopFailure.completion,
                CaptureSourceRun.sourceStopFailureDescription(stopFailure.underlyingError)
            )
        }
    }

    private func stopCaptureRun() async -> CaptureSourceRunSummary {
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

    func updateScene(_ scene: RecordingScene, transition: RecordingSceneTransition = .cut) {
        if isUsingLiveCompositor {
            liveCompositedRecorder.updateScene(scene, transition: transition)
        }
    }

    func updateScreenCapture(settings: RecordingSettings, pickedScreenFilter: SCContentFilter?) async throws {
        switch mode {
        case .liveCompositor:
            try await liveCompositedRecorder.updateScreenCapture(
                settings: settings,
                filter: pickedScreenFilter
            )
        case .captureRun(let captureRun):
            try await captureRun.updateScreenCapture(
                settings: settings,
                pickedScreenFilter: pickedScreenFilter
            )
        case .idle:
            break
        }
    }

    func startEnabledSources(settings: RecordingSettings, pickedScreenFilter: SCContentFilter?) async throws {
        guard case .captureRun(let captureRun) = mode else { return }
        try await captureRun.startEnabledSources(
            settings: settings,
            pickedScreenFilter: pickedScreenFilter
        )
    }

    func startSceneTimeline(settings: RecordingSettings) {
        startSceneTimeline(scene: RecordingScene(settings: settings))
    }

    private func startSceneTimeline(scene: RecordingScene) {
        timelineAccumulatedSeconds = 0
        timelineSegmentStartedAt = Date()
        sceneEvents = [
            RecordingSceneEvent(time: 0, scene: scene)
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

    func appendSceneEventIfNeeded(
        _ scene: RecordingScene,
        state: RecordingState,
        transition: RecordingSceneTransition = .cut
    ) {
        let pendingEvent = pendingSceneEvent(scene: scene, transition: transition)
        appendPendingSceneEvent(pendingEvent, state: state)
    }

    func pendingSceneEvent(
        scene: RecordingScene,
        transition: RecordingSceneTransition
    ) -> PendingRecordingSceneEvent {
        PendingRecordingSceneEvent(
            time: currentSceneTime(),
            scene: scene,
            transition: transition
        )
    }

    func appendPendingSceneEvent(_ pendingEvent: PendingRecordingSceneEvent, state: RecordingState) {
        guard state == .recording || state == .paused || state == .finishing else { return }
        let scene = pendingEvent.scene
        if let last = sceneEvents.last, last.scene == scene {
            if pendingEvent.time < last.time {
                sceneEvents[sceneEvents.count - 1] = RecordingSceneEvent(
                    time: pendingEvent.time,
                    scene: scene,
                    transition: pendingEvent.transition
                )
            }
            return
        }

        let eventTime = pendingEvent.time
        let event = RecordingSceneEvent(
            time: eventTime,
            scene: scene,
            transition: pendingEvent.transition
        )
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
