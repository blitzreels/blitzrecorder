import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

struct ScreenPreviewFrame {
    let sampleBuffer: CMSampleBuffer
    let width: Int
    let height: Int
    let sourceAspectRatio: CGFloat
}

final class ScreenPreviewer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    typealias FrameHandler = @MainActor (ScreenPreviewFrame) -> Void

    private let queue = DispatchQueue(label: "recorder.screen-preview")
    private var stream: SCStream?
    private var frameHandler: FrameHandler?
    private var sourceAspectRatio = SceneLayout.defaultScreenAspectRatio
    private var lastFrameTime = DispatchTime(uptimeNanoseconds: 0)

    var isRunning: Bool {
        stream != nil
    }

    func start(settings: RecordingSettings, filter pickedFilter: SCContentFilter?, frameHandler: @escaping FrameHandler) async throws {
        try? await stop()
        self.frameHandler = frameHandler

        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter

        if let pickedFilter {
            filter = pickedFilter
            let screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            sourceAspectRatio = screenSourceGeometry.aspectRatio()
            let dimensions = ScreenCaptureGeometry.previewDimensions(for: pickedFilter)
            configuration.width = dimensions.width
            configuration.height = dimensions.height
        } else {
            let content = try await SCShareableContent.current
            let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
            filter = source.filter
            let screenSourceGeometry = source.geometry
            sourceAspectRatio = screenSourceGeometry.aspectRatio()
            let dimensions = ScreenCaptureGeometry.previewDimensions(forSourceAspectRatio: sourceAspectRatio)
            configuration.width = dimensions.width
            configuration.height = dimensions.height
            if let sourceRect = source.sourceRect {
                configuration.sourceRect = sourceRect
            }
        }

        let previewFrameRate = min(max(settings.framesPerSecond, 15), 60)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(previewFrameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 4
        configuration.showsCursor = settings.includeCursor
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.streamName = "BlitzRecorder Screen Preview"

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              frameStatus(for: sampleBuffer) == .complete || frameStatus(for: sampleBuffer) == .started,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let now = DispatchTime.now()
        let minimumFrameInterval = 1_000_000_000 / UInt64(60)
        guard now.uptimeNanoseconds - lastFrameTime.uptimeNanoseconds > minimumFrameInterval else {
            return
        }
        lastFrameTime = now

        let sourceAspectRatio = sourceAspectRatio
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        Task { @MainActor [weak self] in
            self?.frameHandler?(ScreenPreviewFrame(
                sampleBuffer: sampleBuffer,
                width: width,
                height: height,
                sourceAspectRatio: sourceAspectRatio
            ))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Screen preview stopped: \(error.localizedDescription)")
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
