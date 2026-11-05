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
    private var configuredDevice: AVCaptureDevice?
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
                        let held = self.configuredDevice.map { device in
                            LocalCameraSessionConfiguration.holdBestFormat(.init(
                                device: device,
                                fps: settings.framesPerSecond,
                                logPrefix: "Camera cutout",
                                sizeLimit: .cutoutPreview
                            ))
                        } ?? false
                        self.session.startRunning()
                        if held { self.configuredDevice?.unlockForConfiguration() }
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
        guard now - lastFrameTime >= 1.0 / 30.0,
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
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard try LocalCameraSessionConfiguration.attachCamera(.init(
            session: session,
            device: device,
            fps: settings.framesPerSecond,
            sizeLimit: .cutoutPreview
        )) else {
            session.commitConfiguration()
            throw RecorderError.noCamera
        }
        configuredDevice = device

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
        LocalCameraSessionConfiguration.selectedCamera(settings: settings)
    }
}
