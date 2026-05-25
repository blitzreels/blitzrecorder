import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit

final class LiveCompositedRecorder: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let renderQueue = DispatchQueue(label: "blitzrecorder.live-compositor")
    private let screenQueue = DispatchQueue(label: "blitzrecorder.live-compositor.screen")
    private let cameraQueue = DispatchQueue(label: "blitzrecorder.live-compositor.camera")
    private let microphoneQueue = DispatchQueue(label: "blitzrecorder.live-compositor.microphone")
    private let lock = NSLock()
    private let ciContext = CIContext()

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

    func start(take: RecordingTake, settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {
        self.settings = settings
        recordingScene = RecordingScene(settings: settings)
        streamError = nil
        writer = try DirectMovieWriter(take: take, settings: settings)

        if settings.enabledSources.contains(.screen) || settings.enabledSources.contains(.systemAudio) {
            try await startScreenStream(settings: settings, filter: pickedFilter)
        }
        if settings.enabledSources.contains(.camera) {
            try startCamera(settings: settings)
        }
        if settings.enabledSources.contains(.microphone) {
            try startMicrophone(settings: settings)
        }
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

        if let screenStream {
            try? await screenStream.stopCapture()
        }
        screenStream = nil

        cameraSession?.stopRunning()
        cameraSession = nil

        microphoneSession?.stopRunning()
        microphoneSession = nil

        let completion = try await writer?.finish() ?? .empty()
        writer = nil
        settings = nil
        resetLatestCaptureState()
        if let streamError {
            self.streamError = nil
            throw RecorderError.captureStreamStopped(streamError.localizedDescription)
        }
        return completion
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
        } else if output is AVCaptureAudioDataOutput {
            writer?.appendAudio(sampleBuffer, source: .microphone)
        }
    }

    private func startScreenStream(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {
        let filter: SCContentFilter
        let dimensions: (width: Int, height: Int)
        let sourceRect: CGRect?
        if let pickedFilter {
            filter = pickedFilter
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(for: settings, pickedFilter: pickedFilter)
            sourceRect = nil
        } else {
            let content = try await SCShareableContent.current
            guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
                throw RecorderError.noDisplay
            }
            let ownProcess = getpid()
            let excludedApplications = content.applications.filter { $0.processID == ownProcess }
            filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(for: settings, display: display)
            sourceRect = ScreenCaptureGeometry.sourceRect(for: display, settings: settings)
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
        guard let device = selectedMicrophone(settings: settings) else {
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

        guard let scene,
              screenBuffer != nil || cameraBuffer != nil else {
            return false
        }

        let dimensions = ScreenCaptureGeometry.outputDimensions(for: settings)
        let canvasRect = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
        var image = scene.canvasBackgroundStyle.ciImage(in: canvasRect)

        for layer in scene.sceneLayout.layerOrder {
            switch layer {
            case .screen:
                guard scene.enabledSources.contains(.screen), let screenBuffer else { continue }
                let rect = targetRect(for: .screen, scene: scene, in: canvasRect)
                image = fill(CIImage(cvPixelBuffer: screenBuffer), into: rect).composited(over: image)
            case .camera:
                guard scene.enabledSources.contains(.camera), let cameraBuffer else { continue }
                let rect = targetRect(for: .camera, scene: scene, in: canvasRect)
                image = fill(
                    CIImage(cvPixelBuffer: cameraBuffer),
                    into: rect,
                    sourceCropAmount: scene.cameraCropAmount,
                    sourceCropPosition: scene.cameraCropPosition
                )
                .composited(over: image)
            }
        }

        ciContext.render(image, to: outputBuffer, bounds: canvasRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        return true
    }

    private func resetLatestCaptureState() {
        lock.lock()
        recordingScene = nil
        latestScreenBuffer = nil
        latestCameraBuffer = nil
        lock.unlock()
    }

    private func targetRect(for kind: SceneLayerKind, scene: RecordingScene, in canvas: CGRect) -> CGRect {
        SceneLayoutProjection.padded(
            SceneLayoutProjection.denormalized(
                SceneLayoutProjection.normalizedFrame(for: kind, in: scene, fillsCanvasWhenOnlyVideoSource: true),
                in: canvas,
                origin: .lowerLeft
            ),
            in: canvas,
            padding: scene.canvasPadding
        )
    }

    private func fit(_ image: CIImage, into target: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let scale = min(target.width / source.width, target.height / source.height)
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let x = target.midX - scaledWidth / 2
        let y = target.midY - scaledHeight / 2
        return image
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private func fill(
        _ image: CIImage,
        into target: CGRect,
        sourceCropAmount: CGPoint = .zero,
        sourceCropPosition: CGPoint = .zero
    ) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let croppedImage = image.cropped(
            to: SourceCropGeometry.cropRectangle(
                source: source,
                target: target,
                sourceCropAmount: sourceCropAmount,
                sourceCropPosition: sourceCropPosition
            )
        )
        return fill(croppedImage, into: target)
    }

    private func fill(_ image: CIImage, into target: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else {
            return image
        }
        let scale = max(target.width / source.width, target.height / source.height)
        let scaledWidth = source.width * scale
        let scaledHeight = source.height * scale
        let x = target.midX - scaledWidth / 2
        let y = target.midY - scaledHeight / 2
        return image
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: x, y: y))
            .cropped(to: target)
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

    private func selectedMicrophone(settings: RecordingSettings) -> AVCaptureDevice? {
        if let selectedMicrophoneID = settings.selectedMicrophoneID,
           let device = AVCaptureDevice(uniqueID: selectedMicrophoneID) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
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
