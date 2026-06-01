import AVFoundation
import CoreMedia
import Foundation

final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "recorder.camera")
    private var writer: VideoFileWriter?
    private var pendingRecording: PendingRecording?
    private var isConfigured = false
    private var configuredDeviceID: String?
    private var configuredFPS: Int?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeoutTask: Task<Void, Never>?

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
            do {
                writer = try makeWriter(for: sampleBuffer, recording: pendingRecording)
            } catch {
                NSLog("Camera writer failed: \(error.localizedDescription)")
                self.pendingRecording = nil
                completeStartup(.failure(error))
                return
            }
        }

        writer?.append(sampleBuffer)
        completeStartup(.success(()))
    }

    private func configureSession(settings: RecordingSettings) throws {
        let selectedDeviceID = settings.selectedCameraID
        if isConfigured,
           configuredDeviceID == selectedDeviceID,
           configuredFPS == settings.framesPerSecond {
            return
        }

        if session.isRunning {
            session.stopRunning()
        }

        guard let device = selectedCamera(settings: settings) else {
            throw RecorderError.noCamera
        }

        session.beginConfiguration()
        LocalCameraSessionConfiguration.configurePreset(on: session)
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        LocalCameraSessionConfiguration.configure(
            device: device,
            fps: settings.framesPerSecond,
            logPrefix: "Camera"
        )

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

    private func makeWriter(for sampleBuffer: CMSampleBuffer, recording: PendingRecording) throws -> VideoFileWriter {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw RecorderError.writerNotReady
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let width = max(2, Int(dimensions.width))
        let height = max(2, Int(dimensions.height))

        NSLog("Camera writer starting at \(width)x\(height)")
        return try VideoFileWriter(
            url: recording.url,
            width: width,
            height: height,
            bitrate: recording.settings.cameraBitrate,
            fps: recording.settings.framesPerSecond,
            outputFormat: recording.settings.outputVideoFormat,
            timelineStartTime: recording.timelineStartTime
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
}

private struct PendingRecording {
    let url: URL
    let settings: RecordingSettings
    let timelineStartTime: CMTime?
}
