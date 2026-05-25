import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "recorder.screen")
    private var stream: SCStream?
    private var writer: VideoFileWriter?
    private var settings: RecordingSettings?
    private var currentDisplay: SCDisplay?
    private var currentZoom: CGFloat = 1.0
    private var currentSourceRect = CGRect.zero
    private var streamError: Error?

    func start(
        url: URL,
        settings: RecordingSettings,
        filter pickedFilter: SCContentFilter?,
        timelineStartTime: CMTime? = nil
    ) async throws {
        self.settings = settings
        currentZoom = 1.0
        streamError = nil

        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let dimensions: (width: Int, height: Int)

        if let pickedFilter {
            filter = pickedFilter
            currentDisplay = nil
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(for: settings, pickedFilter: pickedFilter)
            configuration = streamConfigurationForPickedContent(settings: settings, filter: pickedFilter)
        } else {
            let content = try await SCShareableContent.current
            guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
                throw RecorderError.noDisplay
            }
            currentDisplay = display
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(for: settings, display: display)

            let ownProcess = getpid()
            let excludedApplications = content.applications.filter { $0.processID == ownProcess }
            filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            configuration = streamConfiguration(for: display, settings: settings, zoom: currentZoom)
        }

        writer = try VideoFileWriter(
            url: url,
            width: dimensions.width,
            height: dimensions.height,
            bitrate: settings.screenBitrate,
            fps: settings.framesPerSecond,
            outputFormat: settings.outputVideoFormat,
            timelineStartTime: timelineStartTime
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func pause() {
        writer?.pause()
    }

    func resume() {
        writer?.resume()
    }

    func stop() async throws -> MediaWriterCompletion {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        let completion = try await writer?.finish() ?? .empty()
        writer = nil
        if let streamError {
            self.streamError = nil
            throw RecorderError.captureStreamStopped(streamError.localizedDescription)
        }
        return completion
    }

    func zoomIn() {
        Task { await updateZoom(to: min(currentZoom + 0.25, 3.0)) }
    }

    func zoomOut() {
        Task { await updateZoom(to: max(currentZoom - 0.25, 1.0)) }
    }

    func resetZoom() {
        Task { await updateZoom(to: 1.0) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              frameStatus(for: sampleBuffer) == .complete || frameStatus(for: sampleBuffer) == .started else {
            return
        }
        writer?.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Screen stream stopped: \(error.localizedDescription)")
        streamError = error
    }

    private func updateZoom(to target: CGFloat) async {
        guard let stream, let display = currentDisplay, let settings else { return }

        let start = currentZoom
        let steps = 12
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let eased = 1 - pow(1 - progress, 3)
            let value = start + ((target - start) * eased)
            let configuration = streamConfiguration(for: display, settings: settings, zoom: value)
            try? await stream.updateConfiguration(configuration)
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
        currentZoom = target
    }

    private func streamConfiguration(for display: SCDisplay, settings: RecordingSettings, zoom: CGFloat) -> SCStreamConfiguration {
        let dimensions = ScreenCaptureGeometry.screenCaptureDimensions(for: settings, display: display)
        var sourceRect = ScreenCaptureGeometry.sourceRect(for: display, settings: settings)
        if zoom > 1 {
            let width = sourceRect.width / zoom
            let height = sourceRect.height / zoom
            sourceRect = CGRect(
                x: sourceRect.midX - width / 2,
                y: sourceRect.midY - height / 2,
                width: width,
                height: height
            )
        }
        currentSourceRect = sourceRect

        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 6
        configuration.showsCursor = settings.includeCursor
        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = true
        }
        configuration.capturesAudio = false
        configuration.sourceRect = sourceRect
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.streamName = "BlitzRecorder Screen"
        return configuration
    }

    private func streamConfigurationForPickedContent(settings: RecordingSettings, filter: SCContentFilter) -> SCStreamConfiguration {
        let dimensions = ScreenCaptureGeometry.screenCaptureDimensions(for: settings, pickedFilter: filter)
        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 6
        configuration.showsCursor = settings.includeCursor
        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = true
        }
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.streamName = "BlitzRecorder Picked Screen"
        return configuration
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
