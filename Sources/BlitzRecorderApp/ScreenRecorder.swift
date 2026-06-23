import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "recorder.screen")
    private var stream: SCStream?
    private var writer: VideoFileWriter?
    private var settings: RecordingSettings?
    private var currentDisplay: SCDisplay?
    private var currentPickedFilter: SCContentFilter?
    private var currentDimensions: (width: Int, height: Int)?
    private var currentZoom: CGFloat = 1.0
    private var currentSourceRect = CGRect.zero
    private var streamBackgroundColor: CGColor?
    private var streamError: Error?
    private var intentionallyStoppedStream: SCStream?
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var hasProducedStartupFrame = false

    func start(
        url: URL,
        settings: RecordingSettings,
        filter pickedFilter: SCContentFilter?,
        timelineStartTime: CMTime? = nil
    ) async throws {
        self.settings = settings
        currentZoom = 1.0
        streamError = nil
        intentionallyStoppedStream = nil
        hasProducedStartupFrame = false

        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        let dimensions: (width: Int, height: Int)

        if let pickedFilter {
            filter = pickedFilter
            currentPickedFilter = pickedFilter
            currentDisplay = nil
            let screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: pickedFilter)
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(
                for: settings,
                sourceAspectRatio: screenSourceGeometry.aspectRatio()
            )
            configuration = streamConfigurationForPickedContent(settings: settings, filter: pickedFilter)
        } else {
            currentPickedFilter = nil
            let content = try await SCShareableContent.current
            let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
            currentDisplay = source.display
            dimensions = ScreenCaptureGeometry.screenCaptureDimensions(
                for: settings,
                sourceAspectRatio: source.geometry.aspectRatio()
            )
            filter = source.filter
            configuration = streamConfiguration(
                settings: settings,
                screenSourceGeometry: source.geometry,
                sourceRect: source.sourceRect
            )
        }
        currentDimensions = dimensions

        writer = try VideoFileWriter(
            url: url,
            width: dimensions.width,
            height: dimensions.height,
            bitrate: settings.screenBitrate,
            fps: settings.framesPerSecond,
            outputFormat: settings.sourceVideoFormat,
            timelineStartTime: timelineStartTime
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        try await waitForFirstScreenFrame()
    }

    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {
        guard let stream else {
            self.settings = settings
            return
        }
        self.settings = settings

        if let pickedFilter {
            currentPickedFilter = pickedFilter
            currentDisplay = nil
            try await stream.updateContentFilter(pickedFilter)
            try await stream.updateConfiguration(streamConfigurationForPickedContent(
                settings: settings,
                filter: pickedFilter,
                dimensions: currentDimensions
            ))
            return
        }

        let content = try await SCShareableContent.current
        let source = try ScreenCaptureGeometry.screenSource(for: settings, content: content)
        currentPickedFilter = nil
        currentDisplay = source.display
        try await stream.updateContentFilter(source.filter)
        try await stream.updateConfiguration(streamConfiguration(
            settings: settings,
            screenSourceGeometry: source.geometry,
            sourceRect: source.sourceRect,
            dimensions: currentDimensions
        ))
    }

    func pause() {
        writer?.pause()
    }

    func resume() {
        writer?.resume()
    }

    func stop() async throws -> MediaWriterCompletion {
        if let stream {
            intentionallyStoppedStream = stream
            try? await stream.stopCapture()
        }
        stream = nil
        let completion = try await writer?.finish() ?? .empty()
        writer = nil
        if let streamError {
            self.streamError = nil
            currentDimensions = nil
            let error = RecorderError.captureStreamStopped(streamError.localizedDescription)
            if completion.wroteMedia {
                throw CaptureSourceStopFailure(completion: completion, underlyingError: error)
            }
            throw error
        }
        currentDimensions = nil
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
        completeStartup(.success(()))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard stream !== intentionallyStoppedStream else { return }
        NSLog("Screen stream stopped: \(error.localizedDescription)")
        streamError = error
        completeStartup(.failure(RecorderError.captureStreamStopped(error.localizedDescription)))
    }

    private func waitForFirstScreenFrame() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.hasProducedStartupFrame {
                    continuation.resume()
                    return
                }
                self.startupContinuation = continuation
                self.startupTimeoutTask?.cancel()
                self.startupTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.queue.async {
                        self?.completeStartup(.failure(RecorderError.screenDidNotStart))
                    }
                }
            }
        }
    }

    private func completeStartup(_ result: Result<Void, Error>) {
        if case .success = result {
            hasProducedStartupFrame = true
        }
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

    private func streamConfiguration(
        for display: SCDisplay,
        settings: RecordingSettings,
        zoom: CGFloat,
        dimensions fixedDimensions: (width: Int, height: Int)? = nil
    ) -> SCStreamConfiguration {
        let screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, display: display)
        var sourceRect = screenSourceGeometry.sourceRect(in: CGRect(x: 0, y: 0, width: display.width, height: display.height))
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

        return streamConfiguration(
            settings: settings,
            screenSourceGeometry: screenSourceGeometry,
            sourceRect: sourceRect,
            dimensions: fixedDimensions
        )
    }

    private func streamConfiguration(
        settings: RecordingSettings,
        screenSourceGeometry: ScreenSourceGeometry,
        sourceRect: CGRect?,
        dimensions fixedDimensions: (width: Int, height: Int)? = nil
    ) -> SCStreamConfiguration {
        let dimensions = fixedDimensions ?? ScreenCaptureGeometry.screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: screenSourceGeometry.aspectRatio()
        )
        currentSourceRect = sourceRect ?? .zero

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
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        let backgroundColor = settings.canvasBackgroundStyle.appearance.solidCGColor
        streamBackgroundColor = backgroundColor
        configuration.backgroundColor = backgroundColor
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.streamName = "BlitzRecorder Screen"
        return configuration
    }

    private func streamConfigurationForPickedContent(
        settings: RecordingSettings,
        filter: SCContentFilter,
        dimensions fixedDimensions: (width: Int, height: Int)? = nil
    ) -> SCStreamConfiguration {
        let screenSourceGeometry = ScreenCaptureGeometry.screenSourceGeometry(for: settings, pickedFilter: filter)
        let dimensions = fixedDimensions ?? ScreenCaptureGeometry.screenCaptureDimensions(
            for: settings,
            sourceAspectRatio: screenSourceGeometry.aspectRatio()
        )
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
        let backgroundColor = settings.canvasBackgroundStyle.appearance.solidCGColor
        streamBackgroundColor = backgroundColor
        configuration.backgroundColor = backgroundColor
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
