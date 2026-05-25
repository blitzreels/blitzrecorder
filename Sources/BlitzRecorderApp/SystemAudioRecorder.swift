import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "blitzrecorder.system-audio")
    private var stream: SCStream?
    private var writer: AudioSampleFileWriter?
    var levelHandler: ((Float) -> Void)?
    private var lastLevelTime = DispatchTime(uptimeNanoseconds: 0)
    private var streamError: Error?

    func start(url: URL, settings: RecordingSettings) async throws {
        streamError = nil
        writer = try AudioSampleFileWriter(url: url)

        let content = try await SCShareableContent.current
        guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
            throw RecorderError.noDisplay
        }

        let ownProcess = getpid()
        let excludedApplications = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 2
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.streamName = "BlitzRecorder System Audio"

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
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
        Task { @MainActor [levelHandler] in
            levelHandler?(0)
        }
        return completion
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else {
            return
        }
        publishLevel(from: sampleBuffer)
        writer?.append(sampleBuffer)
    }

    private func publishLevel(from sampleBuffer: CMSampleBuffer) {
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds - lastLevelTime.uptimeNanoseconds > 33_000_000,
              let level = AudioLevelMeter.level(from: sampleBuffer) else {
            return
        }
        lastLevelTime = now

        Task { @MainActor [levelHandler] in
            levelHandler?(level)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("System audio stream stopped: \(error.localizedDescription)")
        streamError = error
    }
}
