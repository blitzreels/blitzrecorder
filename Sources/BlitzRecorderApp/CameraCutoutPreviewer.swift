import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import Vision

final class CameraCutoutPreviewer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias FrameHandler = @MainActor (CGImage) -> Void

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "blitzrecorder.camera-cutout-preview")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    private var frameHandler: FrameHandler?
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()

    override init() {
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        super.init()
    }

    func start(settings: RecordingSettings, frameHandler: @escaping FrameHandler) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    self.frameHandler = frameHandler
                    try self.configureSession(settings: settings)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.frameHandler = nil
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
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= 1.0 / 15.0,
              let frameHandler,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        lastFrameTime = now

        let image = CameraBackgroundMatte.mattedImage(
            for: pixelBuffer,
            request: segmentationRequest,
            sequenceHandler: sequenceHandler
        )
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        Task { @MainActor in
            frameHandler(cgImage)
        }
    }

    private func configureSession(settings: RecordingSettings) throws {
        if session.isRunning {
            session.stopRunning()
        }

        guard let device = selectedCamera(settings: settings) else {
            throw RecorderError.noCamera
        }

        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        try configure(device: device)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecorderError.noCamera
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecorderError.noCamera
        }
        session.addOutput(output)
        session.commitConfiguration()
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
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func configure(device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let hdFormats = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width <= 1920 && dimensions.height <= 1080
        }
        let candidates = hdFormats.isEmpty ? device.formats : hdFormats
        if let format = candidates.sorted(by: { cameraFormatSortKey($0) < cameraFormatSortKey($1) }).first {
            device.activeFormat = format
        }
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
        let areaRank = 10_000_000 - min(9_999_999, Int(dimensions.width) * Int(dimensions.height))
        return String(format: "%06d-%08d", aspectPenalty, areaRank)
    }
}
