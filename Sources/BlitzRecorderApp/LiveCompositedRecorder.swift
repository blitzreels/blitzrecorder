import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

struct LiveRecordingSceneTransition {
    let startScene: RecordingScene
    let targetScene: RecordingScene
    let transition: RecordingSceneTransition
    let startedAt: Date
}

final class LiveCompositedRecorder: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let renderQueue = DispatchQueue(label: "blitzrecorder.live-compositor")
    let screenQueue = DispatchQueue(label: "blitzrecorder.live-compositor.screen")
    let cameraQueue = DispatchQueue(label: "blitzrecorder.live-compositor.camera")
    let microphoneQueue = DispatchQueue(label: "blitzrecorder.live-compositor.microphone")
    let lock = NSLock()
    let renderer = LiveCompositorRenderer()

    var writer: DirectMovieWriter?
    var settings: RecordingSettings?
    var screenStream: SCStream?
    var screenDisplay: SCDisplay?
    var pickedScreenFilter: SCContentFilter?
    var cameraSession: AVCaptureSession?
    var microphoneSession: AVCaptureSession?
    var frameTimer: DispatchSourceTimer?
    var recordingScene: RecordingScene?
    var recordingSceneTransition: LiveRecordingSceneTransition?
    var latestScreenBuffer: CVPixelBuffer?
    var latestCameraBuffer: CVPixelBuffer?
    var hasProducedMicrophoneStartupSample = false
    var backgroundAnimationStartUptime: CFTimeInterval?
    var streamError: Error?
    var intentionallyStoppedScreenStream: SCStream?
    var lastScreenPreviewFrameTime = DispatchTime(uptimeNanoseconds: 0)
    var onCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onScreenPreviewFrame: ScreenPreviewer.FrameHandler?
    private var captureFailureHandler: (@MainActor (ActiveCaptureFailure) -> Void)?
    private var hasReportedCaptureFailure = false
    var captureSessionObservers: [NSObjectProtocol] = []

    var activeScreenCaptureStream: SCStream? {
        screenStream
    }

    func start(
        take: RecordingTake,
        settings: RecordingSettings,
        filter pickedFilter: SCContentFilter?,
        prerollSeconds: Int = 0,
        prerollHandler: (@MainActor (Int) -> Void)? = nil
    ) async throws {
        self.settings = settings
        self.pickedScreenFilter = pickedFilter
        screenDisplay = nil
        var screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings)
        recordingScene = RecordingScene(settings: settings)
        recordingSceneTransition = nil
        streamError = nil
        intentionallyStoppedScreenStream = nil
        lastScreenPreviewFrameTime = DispatchTime(uptimeNanoseconds: 0)
        hasProducedMicrophoneStartupSample = false
        hasReportedCaptureFailure = false
        writer = nil

        if settings.enabledSources.contains(.screen) || settings.enabledSources.contains(.systemAudio) {
            screenSourceGeometry = try await startScreenStream(settings: settings, filter: pickedFilter)
            var scene = RecordingScene(settings: settings)
            scene.screenSourceGeometry = screenSourceGeometry
            recordingScene = scene
            recordingSceneTransition = nil
        }
        if settings.enabledSources.contains(.microphone) {
            try startMicrophone(settings: settings)
        }
        if settings.enabledSources.contains(.camera) {
            try startCamera(settings: settings)
        }
        try await waitForRequiredVideoFrames(settings: settings)
        try await waitForRequiredMicrophoneSample(settings: settings)
        try await runPreroll(seconds: prerollSeconds, handler: prerollHandler)
        writer = try DirectMovieWriter(take: take, settings: settings)
        writer?.onFailure = { [weak self] error in
            let source: CaptureSource = settings.enabledSources.contains(.screen) ? .screen : .camera
            self?.reportCaptureFailure(ActiveCaptureFailure(source: source, error: error))
        }
        startFrameTimer(fps: settings.framesPerSecond)
    }

    func pause() {
        writer?.pause()
    }

    func resume() {
        writer?.resume()
    }

    func setCaptureFailureHandler(_ handler: @escaping @MainActor (ActiveCaptureFailure) -> Void) {
        captureFailureHandler = handler
    }

    func switchMicrophone(to deviceID: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            microphoneQueue.async {
                do {
                    guard let session = self.microphoneSession,
                          let device = MicrophoneDeviceSelection.microphone(id: deviceID) else {
                        throw RecorderError.microphoneUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let previousInputs = session.inputs
                    session.beginConfiguration()
                    previousInputs.forEach { session.removeInput($0) }
                    guard session.canAddInput(input) else {
                        previousInputs.filter { session.canAddInput($0) }.forEach {
                            session.addInput($0)
                        }
                        session.commitConfiguration()
                        throw RecorderError.microphoneUnavailable
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func updateScene(_ scene: RecordingScene, transition: RecordingSceneTransition = .cut) {
        lock.lock()
        if transition.isCut || recordingScene == nil {
            recordingScene = scene
            recordingSceneTransition = nil
        } else {
            let startedAt = Date()
            let startScene = currentRecordingScene(at: startedAt) ?? scene
            recordingScene = scene
            recordingSceneTransition = LiveRecordingSceneTransition(
                startScene: startScene,
                targetScene: scene,
                transition: transition,
                startedAt: startedAt
            )
        }
        lock.unlock()
    }

    func updateScreenCapture(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {
        guard let screenStream else {
            self.settings = settings
            self.pickedScreenFilter = pickedFilter
            return
        }

        let previousSettings = self.settings
        let previousFilter = self.pickedScreenFilter
        do {
            let result = try await applyScreenCaptureUpdate(
                settings: settings,
                pickedFilter: pickedFilter,
                screenStream: screenStream
            )
            self.settings = settings
            self.pickedScreenFilter = pickedFilter
            screenDisplay = result.display
            updateRecordingSceneScreenGeometry(result.geometry)
        } catch {
            guard let previousSettings else {
                throw CaptureSourceRetargetFailure(rollbackFailed: true, underlyingError: error)
            }
            do {
                let rollback = try await applyScreenCaptureUpdate(
                    settings: previousSettings,
                    pickedFilter: previousFilter,
                    screenStream: screenStream
                )
                screenDisplay = rollback.display
                updateRecordingSceneScreenGeometry(rollback.geometry)
            } catch {
                throw CaptureSourceRetargetFailure(rollbackFailed: true, underlyingError: error)
            }
            throw CaptureSourceRetargetFailure(rollbackFailed: false, underlyingError: error)
        }
    }

    private func updateRecordingSceneScreenGeometry(_ screenSourceGeometry: ScreenSourceGeometry) {
        lock.lock()
        if var scene = recordingScene {
            scene.screenSourceGeometry = screenSourceGeometry
            recordingScene = scene
            recordingSceneTransition = nil
        }
        latestScreenBuffer = nil
        lock.unlock()
    }

    func stop() async throws -> MediaWriterCompletion {
        frameTimer?.cancel()
        frameTimer = nil

        if let microphoneSession {
            microphoneSession.beginConfiguration()
            AudioCaptureSessionCleanup.detachAudioOutputs(from: microphoneSession)
            microphoneSession.commitConfiguration()
        }

        if let screenStream {
            intentionallyStoppedScreenStream = screenStream
            try? await screenStream.stopCapture()
        }
        screenStream = nil

        let completion: MediaWriterCompletion
        do {
            completion = try await writer?.finish() ?? .empty()
        } catch {
            tearDownVideoAndMicrophoneSessions()
            writer = nil
            settings = nil
            renderer.reset()
            resetLatestCaptureState()
            throw error
        }

        tearDownVideoAndMicrophoneSessions()
        writer = nil
        settings = nil
        renderer.reset()
        resetLatestCaptureState()
        if let streamError {
            self.streamError = nil
            let error = RecorderError.captureStreamStopped(streamError.localizedDescription)
            if completion.wroteMedia {
                throw CaptureSourceStopFailure(completion: completion, underlyingError: error)
            }
            throw error
        }
        return completion
    }

    private func tearDownVideoAndMicrophoneSessions() {
        captureSessionObservers.forEach(NotificationCenter.default.removeObserver)
        captureSessionObservers.removeAll()
        cameraSession?.stopRunning()
        cameraSession = nil

        if let microphoneSession {
            microphoneSession.stopRunning()
            microphoneSession.beginConfiguration()
            AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: microphoneSession)
            microphoneSession.commitConfiguration()
        }
        microphoneSession = nil
    }

    func reportCaptureFailure(_ failure: ActiveCaptureFailure) {
        lock.lock()
        guard !hasReportedCaptureFailure else {
            lock.unlock()
            return
        }
        hasReportedCaptureFailure = true
        lock.unlock()
        let failureHandler = captureFailureHandler
        Task { @MainActor in
            failureHandler?(failure)
        }
    }
}

extension LiveCompositedRecorder: LiveCompositedRecording {}
