import Foundation

extension LiveCompositedRecorder {
    func waitForRequiredVideoFrames(settings: RecordingSettings) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if hasRequiredVideoFrames(for: RecordingScene(settings: settings)) {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let scene = RecordingScene(settings: settings)
        let missing = missingRequiredVideoFrame(for: scene)
        if missing == .screen {
            throw RecorderError.screenDidNotStart
        }
        if missing == .camera {
            throw RecorderError.cameraDidNotStart
        }
    }

    private func hasRequiredVideoFrames(for scene: RecordingScene) -> Bool {
        let needsScreen = scene.enabledSources.contains(.screen)
        let needsCamera = scene.enabledSources.contains(.camera)
        guard needsScreen || needsCamera else { return true }

        lock.lock()
        let hasScreenBuffer = latestScreenBuffer != nil
        let hasCameraBuffer = latestCameraBuffer != nil
        lock.unlock()

        return (!needsScreen || hasScreenBuffer) && (!needsCamera || hasCameraBuffer)
    }

    private func missingRequiredVideoFrame(for scene: RecordingScene) -> CaptureSource? {
        let needsScreen = scene.enabledSources.contains(.screen)
        let needsCamera = scene.enabledSources.contains(.camera)

        lock.lock()
        let hasScreenBuffer = latestScreenBuffer != nil
        let hasCameraBuffer = latestCameraBuffer != nil
        lock.unlock()

        if needsScreen && !hasScreenBuffer {
            return .screen
        }
        if needsCamera && !hasCameraBuffer {
            return .camera
        }
        return nil
    }

    func waitForRequiredMicrophoneSample(settings: RecordingSettings) async throws {
        guard settings.enabledSources.contains(.microphone) else { return }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if hasMicrophoneStartupSample() {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        throw RecorderError.microphoneDidNotStart
    }

    private func hasMicrophoneStartupSample() -> Bool {
        lock.lock()
        let hasSample = hasProducedMicrophoneStartupSample
        lock.unlock()
        return hasSample
    }

    func runPreroll(
        seconds: Int,
        handler: (@MainActor (Int) -> Void)?
    ) async throws {
        guard seconds > 0 else { return }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            try Task.checkCancellation()
            if let handler {
                await handler(remaining)
            }
            try await Task.sleep(for: .seconds(1))
        }
    }
}
