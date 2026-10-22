import CoreMedia
import Foundation
import ScreenCaptureKit

struct SystemAudioStreamOutputRequest {
    let output: any SCStreamOutput
    let sampleHandlerQueue: DispatchQueue
}

protocol SystemAudioStreaming: AnyObject {
    func attachAudioOutput(_ request: SystemAudioStreamOutputRequest) throws
    func startCapture() async throws
    func stopCapture() async throws
    func updateContentFilter(_ contentFilter: SCContentFilter) async throws
}

extension SCStream: SystemAudioStreaming {
    func attachAudioOutput(_ request: SystemAudioStreamOutputRequest) throws {
        try addStreamOutput(
            request.output,
            type: .audio,
            sampleHandlerQueue: request.sampleHandlerQueue
        )
    }
}

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "blitzrecorder.system-audio")
    private var stream: (any SystemAudioStreaming)?
    private var prewarmedStream: (any SystemAudioStreaming)?
    private var writer: AudioSampleFileWriter?
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }
    private var streamError: Error?
    private var intentionallyStoppedStreamID: ObjectIdentifier?
    private let startupGate = AudioStartupGate(timeoutError: RecorderError.systemAudioDidNotStart)
    private var hasReportedActiveFailure = false
    private var timelineAnchor = RecordingTimelineAnchor()
    var failureHandler: (@MainActor (Error) -> Void)?

    var recordingTimelineOffset: CMTime {
        queue.sync { timelineAnchor.offset }
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) async throws {
        try await start(SystemAudioCaptureStartRequest(
            url: url,
            settings: settings,
            pickedScreenFilter: nil,
            timelineStartTime: timelineStartTime
        ))
    }

    func start(_ request: SystemAudioCaptureStartRequest) async throws {
        streamError = nil
        intentionallyStoppedStreamID = nil
        timelineAnchor.reset(timelineStartTime: request.timelineStartTime)
        startupGate.reset()
        hasReportedActiveFailure = false
        let writer = try AudioSampleFileWriter(
            url: request.url,
            timelineStartTime: request.timelineStartTime,
            stereoBitrate: request.settings.finalAudioBitrate,
            format: request.settings.effectiveSourceAudioFormat
        )
        writer.onFirstSampleWritten = { [weak self] in
            self?.queue.async {
                self?.completeStartup(.success(()))
            }
        }
        writer.onFailure = { [weak self] error in
            self?.queue.async {
                self?.completeStartup(.failure(error))
                self?.reportActiveFailureIfNeeded(error)
            }
        }
        self.writer = writer

        if let prewarmedStream {
            self.prewarmedStream = nil
            try prewarmedStream.attachAudioOutput(.init(output: self, sampleHandlerQueue: queue))
            stream = prewarmedStream
            try await waitForFirstAudioSample()
            return
        }

        let filter = try SystemAudioStreamConfiguration.contentFilter(request.pickedScreenFilter)
        let configuration = SystemAudioStreamConfiguration.configuration(.init(
            streamName: "BlitzRecorder System Audio", includesRecorderUI: request.settings.includesRecorderUI
        ))
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.attachAudioOutput(.init(output: self, sampleHandlerQueue: queue))
        try await stream.startCapture()
        self.stream = stream
        try await waitForFirstAudioSample()
    }

    func adoptMonitoringStream(_ stream: any SystemAudioStreaming) {
        prewarmedStream = stream
    }

    func pause() {
        writer?.pause()
    }

    func update(filter pickedScreenFilter: SCContentFilter?) async throws {
        guard let stream else { return }
        let filter = try SystemAudioStreamConfiguration.contentFilter(pickedScreenFilter)
        try await stream.updateContentFilter(filter)
    }

    func resume() {
        writer?.resume()
    }

    func stop() async throws -> MediaWriterCompletion {
        completeStartup(.failure(RecorderError.systemAudioDidNotStart))
        let writerToFinish = writer
        writer = nil
        if let stream {
            intentionallyStoppedStreamID = ObjectIdentifier(stream)
            try? await stream.stopCapture()
        }
        stream = nil
        if let prewarmedStream {
            intentionallyStoppedStreamID = ObjectIdentifier(prewarmedStream)
            try? await prewarmedStream.stopCapture()
        }
        prewarmedStream = nil
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
        receiveAudioSample(sampleBuffer)
    }

    func receiveAudioSample(_ sampleBuffer: CMSampleBuffer) {
        timelineAnchor.observeFirstSample(sampleBuffer)
        levelPublisher.publish(from: sampleBuffer)
        writer?.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard ObjectIdentifier(stream) != intentionallyStoppedStreamID else { return }
        NSLog("System audio stream stopped: \(error.localizedDescription)")
        streamError = error
        let recorderError = RecorderError.captureStreamStopped(error.localizedDescription)
        completeStartup(.failure(recorderError))
        reportActiveFailureIfNeeded(recorderError)
    }

    private func waitForFirstAudioSample() async throws {
        try await startupGate.wait(on: queue)
    }

    private func completeStartup(_ result: Result<Void, Error>) {
        startupGate.complete(result)
    }

    private func reportActiveFailureIfNeeded(_ error: Error) {
        guard startupGate.hasProducedSample, !hasReportedActiveFailure else { return }
        hasReportedActiveFailure = true
        let failureHandler = failureHandler
        Task { @MainActor in
            failureHandler?(error)
        }
    }
}
