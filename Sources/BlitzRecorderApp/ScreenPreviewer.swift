import CoreImage
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

struct ScreenPreviewFrame {
    let image: CGImage
    let sourceAspectRatio: CGFloat
}

final class ScreenPreviewer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    typealias FrameHandler = @MainActor (ScreenPreviewFrame) -> Void

    private let queue = DispatchQueue(label: "recorder.screen-preview")
    private let ciContext = CIContext()
    private var stream: SCStream?
    private var frameHandler: FrameHandler?
    private var sourceAspectRatio = SceneLayout.defaultScreenAspectRatio
    private var lastFrameTime = DispatchTime(uptimeNanoseconds: 0)

    func start(settings: RecordingSettings, filter pickedFilter: SCContentFilter?, frameHandler: @escaping FrameHandler) async throws {
        try await stop()
        self.frameHandler = frameHandler

        let configuration = SCStreamConfiguration()
        let filter: SCContentFilter

        if let pickedFilter {
            filter = pickedFilter
            sourceAspectRatio = ScreenCaptureGeometry.pickedContentAspectRatio(for: pickedFilter)
            let dimensions = ScreenCaptureGeometry.previewDimensions(for: pickedFilter)
            configuration.width = dimensions.width
            configuration.height = dimensions.height
        } else {
            let content = try await SCShareableContent.current
            guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
                throw RecorderError.noDisplay
            }

            let ownProcess = getpid()
            let excludedApplications = content.applications.filter { $0.processID == ownProcess }
            filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )

            sourceAspectRatio = ScreenCaptureGeometry.screenSourceAspectRatio(
                for: settings,
                fallback: CGFloat(display.width) / CGFloat(display.height)
            )
            let dimensions = ScreenCaptureGeometry.previewDimensions(for: display, settings: settings)
            configuration.width = dimensions.width
            configuration.height = dimensions.height
            configuration.sourceRect = ScreenCaptureGeometry.sourceRect(for: display, settings: settings)
        }

        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
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
            try await stream.stopCapture()
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
        guard now.uptimeNanoseconds - lastFrameTime.uptimeNanoseconds > 33_000_000 else {
            return
        }
        lastFrameTime = now

        let image = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return
        }

        let sourceAspectRatio = sourceAspectRatio
        Task { @MainActor [weak self] in
            self?.frameHandler?(ScreenPreviewFrame(image: cgImage, sourceAspectRatio: sourceAspectRatio))
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
