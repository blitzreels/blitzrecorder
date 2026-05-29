import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

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
    private var cameraSession: AVCaptureSession?
    private var microphoneSession: AVCaptureSession?
    private var frameTimer: DispatchSourceTimer?
    private var recordingScene: RecordingScene?
    private var latestScreenBuffer: CVPixelBuffer?
    private var latestCameraBuffer: CVPixelBuffer?
    private var streamError: Error?
    var onCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?

    func start(
        take: RecordingTake,
        settings: RecordingSettings,
        filter pickedFilter: SCContentFilter?,
        prerollSeconds: Int = 0,
        prerollHandler: (@MainActor (Int) -> Void)? = nil
    ) async throws {
        self.settings = settings
        var screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings)
        recordingScene = RecordingScene(settings: settings)
        streamError = nil
        writer = nil

        if settings.enabledSources.contains(.screen) || settings.enabledSources.contains(.systemAudio) {
            screenSourceGeometry = try await startScreenStream(settings: settings, filter: pickedFilter)
            var scene = RecordingScene(settings: settings)
            scene.screenSourceGeometry = screenSourceGeometry
            recordingScene = scene
        }
        if settings.enabledSources.contains(.microphone) {
            try startMicrophone(settings: settings)
        }
        if settings.enabledSources.contains(.camera) {
            try startCamera(settings: settings)
        }
        await waitForRequiredVideoFrames(settings: settings)
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

    func updateScene(_ scene: RecordingScene) {
        lock.lock()
        recordingScene = scene
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
            throw RecorderError.captureStreamStopped(streamError.localizedDescription)
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
        case .audio:
            writer?.appendAudio(sampleBuffer, source: .systemAudio)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Live compositor screen stream stopped: \(error.localizedDescription)")
        streamError = error
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
        let dimensions: (width: Int, height: Int)
        let sourceRect: CGRect?
        let screenSourceGeometry: ScreenSourceGeometry
        if let pickedFilter {
            filter = pickedFilter
            screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(
                for: settings,
                sourceAspectRatio: screenSourceGeometry.aspectRatio()
            )
            sourceRect = nil
        } else {
            let content = try await SCShareableContent.current
            guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
                throw RecorderError.noDisplay
            }
            let ownProcess = getpid()
            let excludedApplications = content.applications.filter { $0.processID == ownProcess }
            filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, display: display)
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(
                for: settings,
                sourceAspectRatio: screenSourceGeometry.aspectRatio()
            )
            sourceRect = screenSourceGeometry.sourceRect(in: CGRect(x: 0, y: 0, width: display.width, height: display.height))
        }

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

    private func startCamera(settings: RecordingSettings) throws {
        guard let device = selectedCamera(settings: settings) else {
            throw RecorderError.noCamera
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        configure(device: device, fps: settings.framesPerSecond)
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
        let scene = recordingScene
        lock.unlock()

        guard let scene else {
            return false
        }
        return renderer.render(
            screenBuffer: screenBuffer,
            cameraBuffer: cameraBuffer,
            scene: scene,
            settings: settings,
            to: outputBuffer
        )
    }

    private func resetLatestCaptureState() {
        lock.lock()
        recordingScene = nil
        latestScreenBuffer = nil
        latestCameraBuffer = nil
        lock.unlock()
    }

    private func waitForRequiredVideoFrames(settings: RecordingSettings) async {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if hasRequiredVideoFrames(for: RecordingScene(settings: settings)) {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
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
        if let selectedCameraID = settings.selectedCameraID,
           let device = AVCaptureDevice(uniqueID: selectedCameraID) {
            return device
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
            .filter { $0.isConnected && !$0.isSuspended }
            .sorted { lhs, rhs in cameraSortKey(lhs) < cameraSortKey(rhs) }
            .first
    }

    private func configure(device: AVCaptureDevice, fps: Int) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let compatibleFormats = device.formats.filter { format in
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) }
            }
            let fourKFormats = compatibleFormats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width <= 3840 && dimensions.height <= 2160
            }
            let candidates = fourKFormats.isEmpty ? compatibleFormats : fourKFormats
            if let format = candidates.sorted(by: { lhs, rhs in cameraFormatSortKey(lhs) < cameraFormatSortKey(rhs) }).first {
                device.activeFormat = format
            }

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            if shouldForceFrameDuration(for: device),
               device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(fps) }) {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
        } catch {
            NSLog("Live compositor camera configuration failed: \(error.localizedDescription)")
        }
    }

    private func shouldForceFrameDuration(for device: AVCaptureDevice) -> Bool {
        device.deviceType == .builtInWideAngleCamera
    }

    private func cameraSortKey(_ device: AVCaptureDevice) -> String {
        let priority: String
        if device.deviceType == .continuityCamera {
            priority = "0"
        } else if device.deviceType == .external {
            priority = "1"
        } else if device.deviceType == .deskViewCamera {
            priority = "2"
        } else {
            priority = "3"
        }
        return "\(priority)-\(device.localizedName)"
    }

    private func cameraFormatSortKey(_ format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let maxFPS = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return String(format: "%05d-%05d-%05.1f", dimensions.width, dimensions.height, maxFPS)
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
