import AVFoundation
import CoreMedia
import Foundation

final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "recorder.camera")
    private var writer: VideoFileWriter?
    private var frameNormalizer: CameraFrameNormalizer?
    private var pendingStartupSamples: [CMSampleBuffer] = []
    private var pendingRecording: PendingRecording?
    private var isConfigured = false
    private var configuredDeviceID: String?
    private var configuredFPS: Int?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var sessionObservers: [NSObjectProtocol] = []
    private var hasReportedActiveFailure = false
    var failureHandler: (@MainActor (Error) -> Void)?

    override init() {
        super.init()
        let center = NotificationCenter.default
        sessionObservers = [
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                    ?? RecorderError.mediaWriteFailed("Camera session failed.")
                self?.reportActiveFailureIfNeeded(error)
            },
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.reportActiveFailureIfNeeded(
                    RecorderError.mediaWriteFailed("Camera capture was interrupted.")
                )
            }
        ]
    }

    func prewarmPreview(settings: RecordingSettings) {
        queue.async {
            do {
                try self.configureSession(settings: settings)
                self.startSessionIfNeededOnQueue()
            } catch {
                NSLog("Camera prewarm failed: \(error.localizedDescription)")
            }
        }
    }

    func makePreviewLayer(settings: RecordingSettings) async throws -> AVCaptureVideoPreviewLayer {
        let session = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.configureSession(settings: settings)
                    self.startSessionIfNeededOnQueue()
                    continuation.resume(returning: self.session)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) async throws {
        try queue.sync {
            try configureSession(settings: settings)
            pendingRecording = PendingRecording(url: url, settings: settings, timelineStartTime: timelineStartTime)
            writer = nil
            frameNormalizer = nil
            pendingStartupSamples = []
            hasReportedActiveFailure = false
            startSessionIfNeededOnQueue()
        }

        try await waitForFirstRecordingFrame()
    }

    func pause() {
        writer?.pause()
    }

    func resume() {
        writer?.resume()
    }

    func stop() async throws -> MediaWriterCompletion {
        let writerToFinish = await withCheckedContinuation { continuation in
            queue.async {
                self.completeStartup(.failure(RecorderError.cameraDidNotStart))
                self.pendingRecording = nil
                let writer = self.writer
                self.writer = nil
                self.frameNormalizer = nil
                self.pendingStartupSamples = []
                continuation.resume(returning: writer)
            }
        }
        return try await writerToFinish?.finish() ?? .empty()
    }

    func stopSession() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if writer == nil, let pendingRecording {
            pendingStartupSamples.append(sampleBuffer)
            do {
                guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                    throw RecorderError.writerNotReady
                }
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                let normalizationPlan = CMSampleBufferGetImageBuffer(sampleBuffer).flatMap {
                    CameraFrameLetterboxDetector.normalizationPlan(.init(pixelBuffer: $0))
                }
                let decision = CameraFrameNormalizationStartupPolicy.decision(.init(
                    sourceSize: CGSize(
                        width: Int(dimensions.width),
                        height: Int(dimensions.height)
                    ),
                    bufferedSampleCount: pendingStartupSamples.count,
                    normalizationPlan: normalizationPlan
                ))
                guard case .start(let selectedPlan) = decision else {
                    return
                }
                let setup = try makeWriter(.init(
                    sampleBuffers: pendingStartupSamples,
                    recording: pendingRecording,
                    normalizationPlan: selectedPlan
                ))
                writer = setup.writer
                frameNormalizer = setup.frameNormalizer
                pendingStartupSamples = []
                for startupSampleBuffer in setup.startupSampleBuffers {
                    writer?.append(startupSampleBuffer)
                }
                completeStartup(.success(()))
            } catch {
                NSLog("Camera writer failed: \(error.localizedDescription)")
                self.pendingRecording = nil
                pendingStartupSamples = []
                completeStartup(.failure(error))
            }
            return
        }

        if let frameNormalizer {
            guard let normalizedSampleBuffer = frameNormalizer.normalize(sampleBuffer) else {
                NSLog("Camera frame normalization skipped an unreadable frame")
                return
            }
            writer?.append(normalizedSampleBuffer)
        } else {
            writer?.append(sampleBuffer)
        }
        completeStartup(.success(()))
    }

    private func configureSession(settings: RecordingSettings) throws {
        guard let device = selectedCamera(settings: settings) else {
            throw RecorderError.noCamera
        }
        let selectedDeviceID = device.uniqueID
        if isConfigured,
           configuredDeviceID == selectedDeviceID,
           configuredFPS == settings.framesPerSecond {
            return
        }

        if session.isRunning {
            session.stopRunning()
        }

        let cameraIsRunningSomewhere = LocalCameraUsage.isRunningSomewhere(device)

        session.beginConfiguration()
        LocalCameraSessionConfiguration.configurePreset(on: session)
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        LocalCameraSessionConfiguration.configure(.init(
            device: device,
            fps: settings.framesPerSecond,
            logPrefix: "Camera",
            cameraIsRunningSomewhere: cameraIsRunningSomewhere
        ))

        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: queue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        isConfigured = true
        configuredDeviceID = selectedDeviceID
        configuredFPS = settings.framesPerSecond
    }

    private func startSessionIfNeededOnQueue() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    private func selectedCamera(settings: RecordingSettings) -> AVCaptureDevice? {
        LocalCameraSessionConfiguration.selectedCamera(settings: settings)
    }

    private func makeWriter(
        _ request: CameraWriterRequest
    ) throws -> CameraWriterSetup {
        guard let firstSampleBuffer = request.sampleBuffers.first,
              let formatDescription = CMSampleBufferGetFormatDescription(firstSampleBuffer) else {
            throw RecorderError.writerNotReady
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = request.normalizationPlan.map { Int($0.outputSize.width) }
            ?? max(2, Int(dimensions.width))
        let height = request.normalizationPlan.map { Int($0.outputSize.height) }
            ?? max(2, Int(dimensions.height))
        let frameNormalizer = request.normalizationPlan.map(CameraFrameNormalizer.init)
        let startupSampleBuffers: [CMSampleBuffer]
        if let frameNormalizer {
            let normalizedSampleBuffers = request.sampleBuffers.compactMap(frameNormalizer.normalize)
            guard normalizedSampleBuffers.count == request.sampleBuffers.count else {
                throw RecorderError.writerNotReady
            }
            startupSampleBuffers = normalizedSampleBuffers
            NSLog(
                "Camera input normalized from \(dimensions.width)x\(dimensions.height) to \(width)x\(height)"
            )
        } else {
            startupSampleBuffers = request.sampleBuffers
        }

        NSLog("Camera writer starting at \(width)x\(height)")
        let writer = try VideoFileWriter(
            url: request.recording.url,
            width: width,
            height: height,
            bitrate: request.recording.settings.cameraBitrate,
            fps: request.recording.settings.framesPerSecond,
            outputFormat: request.recording.settings.sourceVideoFormat,
            timelineStartTime: request.recording.timelineStartTime
        )
        writer.onFailure = { [weak self] error in
            self?.reportActiveFailureIfNeeded(error)
        }
        return CameraWriterSetup(
            writer: writer,
            frameNormalizer: frameNormalizer,
            startupSampleBuffers: startupSampleBuffers
        )
    }

    private func waitForFirstRecordingFrame() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startupContinuation = continuation
                self.startupTimeoutTask?.cancel()
                self.startupTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.queue.async {
                        self?.completeStartup(.failure(RecorderError.cameraDidNotStart))
                    }
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    private func completeStartup(_ result: Result<Void, Error>) {
        guard let continuation = startupContinuation else { return }
        startupContinuation = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func reportActiveFailureIfNeeded(_ error: Error) {
        queue.async {
            guard self.pendingRecording != nil, !self.hasReportedActiveFailure else { return }
            self.hasReportedActiveFailure = true
            let failureHandler = self.failureHandler
            Task { @MainActor in
                failureHandler?(error)
            }
        }
    }
}

private struct PendingRecording {
    let url: URL
    let settings: RecordingSettings
    let timelineStartTime: CMTime?
}

private struct CameraWriterRequest {
    let sampleBuffers: [CMSampleBuffer]
    let recording: PendingRecording
    let normalizationPlan: CameraFrameNormalizationPlan?
}

private struct CameraWriterSetup {
    let writer: VideoFileWriter
    let frameNormalizer: CameraFrameNormalizer?
    let startupSampleBuffers: [CMSampleBuffer]
}
