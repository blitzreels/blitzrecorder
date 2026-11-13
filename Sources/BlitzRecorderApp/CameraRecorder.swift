import AVFoundation
import CoreMedia
import Foundation

final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias ThumbnailHandler = @MainActor (CMSampleBuffer) -> Void

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "recorder.camera")
    private var writer: VideoFileWriter?
    private var frameConformer: CameraFrameConformer?
    private var recordingSourceSize: CGSize?
    private var awaitedStartupSize: CGSize?
    private var staleStartupFrames = 0
    private var startupFrameTimeoutSeconds: UInt64 = 2
    private var formatRestoresLeft = CameraRecorder.formatRestoresPerTake
    private static let formatRestoresPerTake = 3
    private static let staleStartupFrameLimit = 30
    private var pendingStartupSamples: [CMSampleBuffer] = []
    private var pendingRecording: PendingRecording?
    private var isConfigured = false
    private var configuredDeviceID: String?
    private var configuredDevice: AVCaptureDevice?
    private var configuredFPS: Int?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var sessionObservers: [NSObjectProtocol] = []
    private var hasReportedActiveFailure = false
    private var blackFrameGenerator: CameraBlackFrameGenerator?
    private var blackFrameTimer: DispatchSourceTimer?
    private var lastForwardedPresentationTime: CMTime?
    private var previewFormatRecovery: CameraPreviewFormatRecovery?
    private var latestDelivery: CameraDeliverySnapshot?
    private var lastDeliveryTime = -TimeInterval.infinity
    private var thumbnailHandler: ThumbnailHandler?
    private var lastThumbnailTime = -TimeInterval.infinity
    private var thumbnailIsOnItsWay = false
    private var thumbnailInterval: TimeInterval = 1
    var failureHandler: (@MainActor (Error) -> Void)?
    var deliveryWarningHandler: (@MainActor (String) -> Void)?
    /// An extra angle records only its own camera; recording the default camera instead would duplicate Camera 1.
    private let fallsBackToDefaultCamera: Bool

    override convenience init() {
        self.init(fallsBackToDefaultCamera: true)
    }

    init(fallsBackToDefaultCamera: Bool) {
        self.fallsBackToDefaultCamera = fallsBackToDefaultCamera
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

    func setThumbnailHandler(_ handler: ThumbnailHandler?) {
        queue.sync {
            thumbnailHandler = handler
            lastThumbnailTime = -TimeInterval.infinity
        }
    }

    func setPopoutPreviewEnabled(_ enabled: Bool) {
        queue.async { self.thumbnailInterval = enabled ? 0 : 1 }
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
        await withCheckedContinuation { continuation in
            queue.async {
                if let request = self.formatRequest() {
                    LocalCameraSessionConfiguration.restoreBestFormat(request)
                }
                self.previewFormatRecovery = CameraPreviewFormatRecovery(startedAt: ProcessInfo.processInfo.systemUptime)
                continuation.resume()
            }
        }
        layer.videoGravity = .resizeAspect
        return layer
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) async throws {
        try queue.sync {
            try configureSession(settings: settings)
            pendingRecording = PendingRecording(url: url, settings: settings, timelineStartTime: timelineStartTime)
            writer = nil
            frameConformer = nil
            recordingSourceSize = nil
            formatRestoresLeft = Self.formatRestoresPerTake
            pendingStartupSamples = []
            hasReportedActiveFailure = false
            prepareStartupFormatOnQueue()
            stopBlackFramesOnQueue()
            blackFrameGenerator = nil
            lastForwardedPresentationTime = nil
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
                self.stopBlackFramesOnQueue()
                self.pendingRecording = nil
                let writer = self.writer
                self.writer = nil
                self.frameConformer = nil
                self.recordingSourceSize = nil
                self.awaitedStartupSize = nil
                self.blackFrameGenerator = nil
                self.lastForwardedPresentationTime = nil
                self.pendingStartupSamples = []
                continuation.resume(returning: writer)
            }
        }
        return try await writerToFinish?.finish() ?? .empty()
    }

    func stopSession() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopBlackFramesOnQueue()
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.lastThumbnailTime = -TimeInterval.infinity
                continuation.resume()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        restorePreviewFormatIfNeeded(sampleBuffer)
        noteDelivery(sampleBuffer)
        offerThumbnail(sampleBuffer)
        stopBlackFramesOnQueue()
        hasReportedActiveFailure = false
        prepareBlackFrameGeneratorIfNeeded(sampleBuffer)
        if writer == nil, let pendingRecording {
            pendingStartupSamples.append(sampleBuffer)
            do {
                guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                    throw RecorderError.writerNotReady
                }
                let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                let frameSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
                if let awaitedStartupSize, frameSize != awaitedStartupSize,
                   staleStartupFrames < Self.staleStartupFrameLimit {
                    staleStartupFrames += 1
                    pendingStartupSamples.removeLast()
                    return
                }
                awaitedStartupSize = nil
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
                frameConformer = setup.frameConformer
                recordingSourceSize = frameSize
                reportDeliveryOnQueue(pictureSize: setup.pictureSize)
                pendingStartupSamples = []
                for startupSampleBuffer in setup.startupSampleBuffers {
                    appendRecordingSampleOnQueue(startupSampleBuffer)
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

        noteRecordingSourceSizeOnQueue(sampleBuffer)
        appendRecordingSampleOnQueue(sampleBuffer)
        completeStartup(.success(()))
    }

    private func prepareStartupFormatOnQueue() {
        awaitedStartupSize = nil
        staleStartupFrames = 0
        startupFrameTimeoutSeconds = 2
        guard session.isRunning, let request = formatRequest() else { return }
        guard LocalCameraSessionConfiguration.restoreBestFormat(request) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(request.device.activeFormat.formatDescription)
        awaitedStartupSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        startupFrameTimeoutSeconds = 6
    }

    private func noteRecordingSourceSizeOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard let recordingSourceSize,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        guard size != recordingSourceSize else { return }
        self.recordingSourceSize = size
        guard let request = formatRequest() else { return }
        guard formatRestoresLeft > 0 else {
            reportDeliveryOnQueue(pictureSize: size)
            return
        }
        formatRestoresLeft -= 1
        queue.async { LocalCameraSessionConfiguration.restoreBestFormat(request) }
    }

    private func reportDeliveryOnQueue(pictureSize: CGSize) {
        guard let device = configuredDevice,
              let handler = deliveryWarningHandler,
              let shortfall = LocalCameraDelivery.shortfall(.init(
                device: device,
                pictureSize: pictureSize,
                sourceSize: latestDelivery?.sourceSize ?? pictureSize,
                fps: configuredFPS ?? RecordingSettings().framesPerSecond
              )) else { return }
        let warning = shortfall.recordingWarning
        NSLog("Camera delivery: \(warning)")
        Task { @MainActor in handler(warning) }
    }

    private func formatRequest() -> LocalCameraDeviceConfigurationRequest? {
        configuredDevice.map {
            LocalCameraDeviceConfigurationRequest(
                device: $0,
                fps: configuredFPS ?? RecordingSettings().framesPerSecond,
                logPrefix: "Camera",
                sizeLimit: .recording
            )
        }
    }

    private func restorePreviewFormatIfNeeded(_ sample: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        if previewFormatRecovery?.isComplete(at: now) == true { previewFormatRecovery = nil }
        guard previewFormatRecovery?.isReady(at: now) == true, let request = formatRequest(),
              let expected = LocalCameraSessionConfiguration.bestFormat(.init(
                device: request.device, fps: request.fps, sizeLimit: request.sizeLimit)),
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(expected.formatDescription)
        let recovery = CameraPreviewFormatRecovery.Request(
            now: now,
            sourceSize: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)),
            expectedSize: CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        )
        guard previewFormatRecovery?.shouldRestore(recovery) == true else { return }
        LocalCameraSessionConfiguration.restoreBestFormat(request)
        lastDeliveryTime = -TimeInterval.infinity
    }

    private func noteDelivery(_ sample: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDeliveryTime >= 1, let device = configuredDevice,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        lastDeliveryTime = now
        let source = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let active = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        latestDelivery = CameraDeliverySnapshot(
            cameraName: device.localizedName,
            sourceSize: source,
            pictureSize: CameraFrameLetterboxDetector.normalizationPlan(.init(pixelBuffer: buffer))?.outputSize ?? source,
            activeFormatSize: CGSize(width: Int(active.width), height: Int(active.height)),
            requestedFPS: configuredFPS ?? 30,
            sampleTime: now
        )
    }

    func deliverySnapshot() -> CameraDeliverySnapshot? { queue.sync { latestDelivery } }

    #if DEBUG
    func probeDelivery(settings: RecordingSettings) async throws -> CameraDeliverySnapshot? {
        let wasRunning = queue.sync { session.isRunning }
        let started = ProcessInfo.processInfo.systemUptime
        _ = try await makePreviewLayer(settings: settings)
        try await Task.sleep(for: .seconds(3))
        let snapshot = deliverySnapshot()
        if !wasRunning { await stopSession() }
        return snapshot.flatMap { $0.sampleTime >= started ? $0 : nil }
    }
    #endif

    private func offerThumbnail(_ sampleBuffer: CMSampleBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let thumbnailHandler,
              !thumbnailIsOnItsWay,
              now - lastThumbnailTime >= thumbnailInterval,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        lastThumbnailTime = now
        thumbnailIsOnItsWay = true
        Task { @MainActor in
            thumbnailHandler(sampleBuffer)
            self.queue.async { self.thumbnailIsOnItsWay = false }
        }
    }

    func continueWithBlackFrames() {
        queue.async {
            guard self.pendingRecording != nil,
                  self.writer != nil,
                  let generator = self.blackFrameGenerator,
                  self.blackFrameTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            let interval = max(1.0 / 120.0, generator.frameDuration.seconds)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in
                self?.appendBlackFrameOnQueue()
            }
            self.blackFrameTimer = timer
            timer.resume()
        }
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

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        try LocalCameraSessionConfiguration.attachCamera(.init(
            session: session,
            device: device,
            fps: settings.framesPerSecond,
            sizeLimit: .recording
        ))

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
        configuredDevice = device
        configuredFPS = settings.framesPerSecond
    }

    private func startSessionIfNeededOnQueue() {
        guard !session.isRunning else { return }
        let held = formatRequest().map(LocalCameraSessionConfiguration.holdBestFormat) ?? false
        session.startRunning()
        if held { configuredDevice?.unlockForConfiguration() }
    }

    private func prepareBlackFrameGeneratorIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        guard blackFrameGenerator == nil,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let pendingRecording else { return }
        blackFrameGenerator = try? CameraBlackFrameGenerator(.init(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
            framesPerSecond: pendingRecording.settings.framesPerSecond
        ))
    }

    private func appendBlackFrameOnQueue() {
        guard let generator = blackFrameGenerator else { return }
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        let minimumTime = lastForwardedPresentationTime.map {
            CMTimeAdd($0, generator.frameDuration)
        } ?? hostTime
        let presentationTime = CMTimeCompare(hostTime, minimumTime) >= 0 ? hostTime : minimumTime
        guard let sampleBuffer = generator.sampleBuffer(at: presentationTime) else { return }
        appendRecordingSampleOnQueue(sampleBuffer)
    }

    private func appendRecordingSampleOnQueue(_ sampleBuffer: CMSampleBuffer) {
        let outputSample: CMSampleBuffer
        if let frameConformer {
            guard let conformedSampleBuffer = frameConformer.conform(sampleBuffer) else {
                NSLog("Camera frame conforming skipped an unreadable frame")
                return
            }
            outputSample = conformedSampleBuffer
        } else {
            outputSample = sampleBuffer
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(outputSample)
        guard presentationTime.isValid else { return }
        if let lastForwardedPresentationTime,
           CMTimeCompare(presentationTime, lastForwardedPresentationTime) <= 0 {
            return
        }
        self.lastForwardedPresentationTime = presentationTime
        writer?.append(outputSample)
    }

    private func stopBlackFramesOnQueue() {
        blackFrameTimer?.cancel()
        blackFrameTimer = nil
    }

    private func selectedCamera(settings: RecordingSettings) -> AVCaptureDevice? {
        guard fallsBackToDefaultCamera else {
            return settings.selectedCameraID
                .flatMap(AVCaptureDevice.init(uniqueID:))
                .flatMap { $0.isConnected && !$0.isSuspended ? $0 : nil }
        }
        return LocalCameraSessionConfiguration.selectedCamera(settings: settings)
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
        let outputSize = CGSize(width: width, height: height)
        let frameConformer = CameraFrameConformer(.init(
            outputSize: outputSize,
            sourceSize: CGSize(width: Int(dimensions.width), height: Int(dimensions.height)),
            plan: request.normalizationPlan
        ))
        let startupSampleBuffers = request.sampleBuffers.compactMap(frameConformer.conform)
        guard startupSampleBuffers.count == request.sampleBuffers.count else {
            throw RecorderError.writerNotReady
        }
        if request.normalizationPlan != nil {
            NSLog("Camera input normalized from \(dimensions.width)x\(dimensions.height) to \(width)x\(height)")
        }

        let bitrate = request.recording.settings.cameraBitrate(pictureSize: outputSize)
        NSLog("Camera writer starting at \(width)x\(height), \(bitrate) bps")
        let writer = try VideoFileWriter(
            url: request.recording.url,
            width: width,
            height: height,
            bitrate: bitrate,
            fps: request.recording.settings.framesPerSecond,
            outputFormat: request.recording.settings.sourceVideoFormat,
            timelineStartTime: request.recording.timelineStartTime
        )
        writer.onFailure = { [weak self] error in
            self?.reportActiveFailureIfNeeded(error)
        }
        return CameraWriterSetup(
            writer: writer,
            frameConformer: frameConformer,
            pictureSize: outputSize,
            startupSampleBuffers: startupSampleBuffers
        )
    }

    private func waitForFirstRecordingFrame() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startupContinuation = continuation
                self.startupTimeoutTask?.cancel()
                self.startupTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: (self?.startupFrameTimeoutSeconds ?? 2) * 1_000_000_000)
                    self?.queue.async {
                        self?.completeStartup(.failure(RecorderError.cameraDidNotStart))
                    }
                }

                self.startSessionIfNeededOnQueue()
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
    let frameConformer: CameraFrameConformer
    let pictureSize: CGSize
    let startupSampleBuffers: [CMSampleBuffer]
}
