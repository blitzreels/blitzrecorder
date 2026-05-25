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
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        configure(device: device, fps: settings.framesPerSecond)

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

            if let format = candidates.sorted(by: { lhs, rhs in
                cameraFormatSortKey(lhs) < cameraFormatSortKey(rhs)
            }).first {
                device.activeFormat = format
            }

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            if shouldForceFrameDuration(for: device),
               device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(fps) }) {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
        } catch {
            NSLog("Camera configuration failed: \(error.localizedDescription)")
        }
    }

    private func shouldForceFrameDuration(for device: AVCaptureDevice) -> Bool {
        device.deviceType == .builtInWideAngleCamera
    }

    private func selectedCamera(settings: RecordingSettings) -> AVCaptureDevice? {
        if let selectedCameraID = settings.selectedCameraID,
           let device = AVCaptureDevice(uniqueID: selectedCameraID),
           device.isConnected,
           !device.isSuspended {
            return device
        }

        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
            .filter { $0.isConnected && !$0.isSuspended }
            .sorted { lhs, rhs in
                cameraSortKey(lhs) < cameraSortKey(rhs)
            }

        if let device = devices.first {
            return device
        }

        let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard fallback?.isConnected == true, fallback?.isSuspended == false else {
            return nil
        }
        return fallback
    }

    private func cameraSortKey(_ device: AVCaptureDevice) -> String {
        let priority: String
        if device.isContinuityCamera {
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
        let width = max(1, Int(dimensions.width))
        let height = max(1, Int(dimensions.height))
        let aspect = Double(width) / Double(height)
        let aspectPenalty = Int((abs(aspect - Double(SceneLayout.cameraAspectRatio)) * 10_000).rounded())
        let areaRank = 10_000_000 - min(9_999_999, width * height)
        return String(format: "%06d-%08d", aspectPenalty, areaRank)
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
