import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "blitzrecorder.system-audio")
    private var stream: SCStream?
    private var writer: AudioSampleFileWriter?
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }
    private var streamError: Error?
    private var intentionallyStoppedStream: SCStream?

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) async throws {
        streamError = nil
        intentionallyStoppedStream = nil
        writer = try AudioSampleFileWriter(
            url: url,
            timelineStartTime: timelineStartTime,
            stereoBitrate: settings.finalAudioBitrate,
            format: settings.effectiveSourceAudioFormat
        )

        let filter = try await SystemAudioStreamConfiguration.contentFilter(settings: settings)
        let configuration = SystemAudioStreamConfiguration.configuration(streamName: "BlitzRecorder System Audio")
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
        let writerToFinish = writer
        writer = nil
        if let stream {
            intentionallyStoppedStream = stream
            try? await stream.stopCapture()
        }
        stream = nil
        let completion = try await writerToFinish?.finish() ?? .empty()
        levelPublisher.reset()
        if let streamError {
            self.streamError = nil
            let error = RecorderError.captureStreamStopped(streamError.localizedDescription)
            if completion.wroteMedia {
                throw CaptureSourceStopFailure(completion: completion, underlyingError: error)
            }
            throw error
        }
        return completion
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else {
            return
        }
        levelPublisher.publish(from: sampleBuffer)
        writer?.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard stream !== intentionallyStoppedStream else { return }
        NSLog("System audio stream stopped: \(error.localizedDescription)")
        streamError = error
    }
}
