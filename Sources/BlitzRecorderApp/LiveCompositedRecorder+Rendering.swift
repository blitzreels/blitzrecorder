import AVFoundation
import CoreMedia
import Foundation

extension LiveCompositedRecorder {
    func startFrameTimer(fps: Int) {
        let timer = DispatchSource.makeTimerSource(queue: renderQueue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / max(1, fps)), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.renderFrame()
        }
        frameTimer = timer
        timer.resume()
    }

    private func renderFrame() {
        guard let writer, let settings else { return }
        let sourceTime = CMClockGetTime(CMClockGetHostTimeClock())
        writer.appendVideo(sourceTime: sourceTime) { [weak self] outputBuffer in
            self?.render(to: outputBuffer, settings: settings) ?? false
        }
    }

    private func render(to outputBuffer: CVPixelBuffer, settings: RecordingSettings) -> Bool {
        lock.lock()
        let screenBuffer = latestScreenBuffer
        let cameraBuffer = latestCameraBuffer
        let scene = currentRecordingScene(at: Date())
        lock.unlock()

        guard let scene else {
            return false
        }
        return renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: cameraBuffer,
            scene: scene,
            settings: settings,
            backgroundPhase: backgroundAnimationPhase(for: scene),
            to: outputBuffer
        )
    }

    /// Loop phase (0...1) for the animated background, anchored to the first
    /// animated frame. Runs on `renderQueue` only. `nil` when not animating.
    private func backgroundAnimationPhase(for scene: RecordingScene) -> Double? {
        guard scene.canvasBackgroundAnimated, scene.canvasBackgroundStyle.supportsBackgroundAnimation else {
            backgroundAnimationStartUptime = nil
            return nil
        }
        let now = ProcessInfo.processInfo.systemUptime
        if backgroundAnimationStartUptime == nil {
            backgroundAnimationStartUptime = now
        }
        let elapsed = now - (backgroundAnimationStartUptime ?? now)
        return (elapsed / CanvasAppearance.animationLoopDuration).truncatingRemainder(dividingBy: 1)
    }

    func currentRecordingScene(at date: Date) -> RecordingScene? {
        guard let transition = recordingSceneTransition else {
            return recordingScene
        }

        let elapsed = date.timeIntervalSince(transition.startedAt)
        guard elapsed < transition.transition.duration else {
            recordingScene = transition.targetScene
            recordingSceneTransition = nil
            return transition.targetScene
        }

        return transition.startScene.interpolated(
            to: transition.targetScene,
            progress: transition.transition.progress(elapsed: elapsed)
        )
    }

    func resetLatestCaptureState() {
        lock.lock()
        recordingScene = nil
        recordingSceneTransition = nil
        latestScreenBuffer = nil
        latestCameraBuffer = nil
        hasProducedMicrophoneStartupSample = false
        backgroundAnimationStartUptime = nil
        lock.unlock()
    }
}
