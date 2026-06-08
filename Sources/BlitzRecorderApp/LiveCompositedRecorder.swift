import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

private struct LiveRecordingSceneTransition {
    let startScene: RecordingScene
    let targetScene: RecordingScene
    let transition: RecordingSceneTransition
    let startedAt: Date
}

final class LiveCompositedRecorder: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let renderQueue = DispatchQueue(label: "blitzrecorder.live-compositor")
    private let screenQueue = DispatchQueue(label: "blitzrecorder.live-compositor.screen")
    private let cameraQueue = DispatchQueue(label: "blitzrecorder.live-compositor.camera")
    private let microphoneQueue = DispatchQueue(label: "blitzrecorder.live-compositor.microphone")
    private let lock = NSLock()
    private let renderer = LiveCompositorRenderer()

    private var writer: DirectMovieWriter?
    private var settings: RecordingSettings?
    private var screenStream: SCStream?
    private var screenDisplay: SCDisplay?
    private var pickedScreenFilter: SCContentFilter?
    private var cameraSession: AVCaptureSession?
    private var microphoneSession: AVCaptureSession?
    private var frameTimer: DispatchSourceTimer?
    private var recordingScene: RecordingScene?
    private var recordingSceneTransition: LiveRecordingSceneTransition?
    private var latestScreenBuffer: CVPixelBuffer?
    private var latestCameraBuffer: CVPixelBuffer?
    private var hasProducedMicrophoneStartupSample = false
    private var backgroundAnimationStartUptime: CFTimeInterval?
    private var streamError: Error?
    private var intentionallyStoppedScreenStream: SCStream?
    private var lastScreenPreviewFrameTime = DispatchTime(uptimeNanoseconds: 0)
    var onCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onScreenPreviewFrame: ScreenPreviewer.FrameHandler?

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
        startFrameTimer(fps: settings.framesPerSecond)
    }

    func pause() {
        writer?.pause()
    }

    func resume() {
        writer?.resume()
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
            return
        }
        self.settings = settings
        self.pickedScreenFilter = pickedFilter

        let configuration: SCStreamConfiguration
        let screenSourceGeometry: ScreenSourceGeometry
        if let pickedFilter {
            screenDisplay = nil
            screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            configuration = screenStreamConfiguration(
                settings: settings,
                screenSourceGeometry: screenSourceGeometry,
                sourceRect: nil
            )
            try await screenStream.updateContentFilter(pickedFilter)
        } else {
            let content = try await SCShareableContent.current
            let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
            screenDisplay = source.display
            screenSourceGeometry = source.geometry
            configuration = screenStreamConfiguration(
                settings: settings,
                screenSourceGeometry: screenSourceGeometry,
                sourceRect: source.sourceRect
            )
            try await screenStream.updateContentFilter(source.filter)
        }

        try await screenStream.updateConfiguration(configuration)
        updateRecordingSceneScreenGeometry(screenSourceGeometry)
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

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            guard frameStatus(for: sampleBuffer) == .complete || frameStatus(for: sampleBuffer) == .started,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            lock.lock()
            latestScreenBuffer = pixelBuffer
            lock.unlock()
            publishScreenPreviewFrame(sampleBuffer, imageBuffer: pixelBuffer)
        case .audio:
            writer?.appendAudio(sampleBuffer, source: .systemAudio)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard stream !== intentionallyStoppedScreenStream else { return }
        NSLog("Live compositor screen stream stopped: \(error.localizedDescription)")
        streamError = error
    }

    private func publishScreenPreviewFrame(_ sampleBuffer: CMSampleBuffer, imageBuffer: CVPixelBuffer) {
        guard let onScreenPreviewFrame else { return }

        let now = DispatchTime.now()
        let minimumFrameInterval = 1_000_000_000 / UInt64(60)
        guard now.uptimeNanoseconds - lastScreenPreviewFrameTime.uptimeNanoseconds > minimumFrameInterval else {
            return
        }
        lastScreenPreviewFrameTime = now

        lock.lock()
        let sourceAspectRatio = recordingScene?.screenSourceGeometry.aspectRatio()
            ?? SceneLayout.defaultScreenAspectRatio
        lock.unlock()

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        Task { @MainActor [onScreenPreviewFrame, sampleBuffer] in
            onScreenPreviewFrame(ScreenPreviewFrame(
                sampleBuffer: sampleBuffer,
                width: width,
                height: height,
                sourceAspectRatio: sourceAspectRatio
            ))
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lock.lock()
            latestCameraBuffer = pixelBuffer
            lock.unlock()
            publishCameraPreviewFrame(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            lock.lock()
            hasProducedMicrophoneStartupSample = true
            lock.unlock()
            writer?.appendAudio(sampleBuffer, source: .microphone)
        }
    }

    private func publishCameraPreviewFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        guard width > 0, height > 0 else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary?.self) {
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        DispatchQueue.main.async { [weak self, sampleBuffer] in
            self?.onCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
    }

    private func startScreenStream(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws -> ScreenSourceGeometry {
        let filter: SCContentFilter
        let sourceRect: CGRect?
        let screenSourceGeometry: ScreenSourceGeometry
        if let pickedFilter {
            self.pickedScreenFilter = pickedFilter
            screenDisplay = nil
            filter = pickedFilter
            screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            sourceRect = nil
        } else {
            let content = try await SCShareableContent.current
            let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
            screenDisplay = source.display
            self.pickedScreenFilter = nil
            filter = source.filter
            screenSourceGeometry = source.geometry
            sourceRect = source.sourceRect
        }

        let configuration = screenStreamConfiguration(
            settings: settings,
            screenSourceGeometry: screenSourceGeometry,
            sourceRect: sourceRect
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        if settings.enabledSources.contains(.screen) {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        }
        if settings.enabledSources.contains(.systemAudio) {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: screenQueue)
        }
        try await stream.startCapture()
        screenStream = stream
        return screenSourceGeometry
    }

    private func screenStreamConfiguration(
        settings: RecordingSettings,
        screenSourceGeometry: ScreenSourceGeometry,
        sourceRect: CGRect?
    ) -> SCStreamConfiguration {
        let dimensions = ScreenCaptureGeometry.screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: screenSourceGeometry.aspectRatio()
        )
        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6
        configuration.showsCursor = settings.includeCursor
        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = true
        }
        configuration.capturesAudio = settings.enabledSources.contains(.systemAudio)
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.streamName = "BlitzRecorder Live Compositor"
        return configuration
    }

    private func startCamera(settings: RecordingSettings) throws {
        guard let device = selectedCamera(settings: settings) else {
            throw RecorderError.noCamera
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        LocalCameraSessionConfiguration.configurePreset(on: session)

        LocalCameraSessionConfiguration.configure(
            device: device,
            fps: settings.framesPerSecond,
            logPrefix: "Live compositor"
        )
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.noCamera
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        guard session.canAddOutput(output) else {
            throw RecorderError.writerNotReady
        }
        session.addOutput(output)
        session.commitConfiguration()

        cameraSession = session
        cameraQueue.async {
            session.startRunning()
        }
    }

    private func startMicrophone(settings: RecordingSettings) throws {
        guard let device = MicrophoneDeviceSelection.selectedMicrophone(settings: settings) else {
            throw RecorderError.microphoneUnavailable
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.microphoneUnavailable
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: microphoneQueue)
        guard session.canAddOutput(output) else {
            throw RecorderError.writerNotReady
        }
        session.addOutput(output)
        session.commitConfiguration()

        microphoneSession = session
        microphoneQueue.async {
            session.startRunning()
        }
    }

    private func startFrameTimer(fps: Int) {
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

    private func currentRecordingScene(at date: Date) -> RecordingScene? {
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

    private func resetLatestCaptureState() {
        lock.lock()
        recordingScene = nil
        recordingSceneTransition = nil
        latestScreenBuffer = nil
        latestCameraBuffer = nil
        hasProducedMicrophoneStartupSample = false
        backgroundAnimationStartUptime = nil
        lock.unlock()
    }

    private func waitForRequiredVideoFrames(settings: RecordingSettings) async throws {
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

    private func waitForRequiredMicrophoneSample(settings: RecordingSettings) async throws {
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

    private func runPreroll(
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

    private func selectedCamera(settings: RecordingSettings) -> AVCaptureDevice? {
        LocalCameraSessionConfiguration.selectedCamera(settings: settings)
    }

    private func frameStatus(for sampleBuffer: CMSampleBuffer) -> SCFrameStatus {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return .complete
        }
        return status
    }
}

extension LiveCompositedRecorder: LiveCompositedRecording {}
