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
    private var recoverySegments: AudioRecoverySegmentWriter?
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }
    private var streamError: Error?
    /// Only the current stream may write or report a stop: a replaced stream can still deliver a few buffers.
    private let currentStreamLock = NSLock()
    private var currentStreamID: ObjectIdentifier?
    /// Read and written on `queue` only.
    private var lastSampleEnd = CMTime.invalid
    private let startupGate = AudioStartupGate(timeoutError: RecorderError.systemAudioDidNotStart)
    private var hasReportedActiveFailure = false
    private var includesRecorderUI = false
    private var timelineAnchor = RecordingTimelineAnchor()
    private static let timeTolerance = CMTime(value: 1, timescale: 1_000)
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
        setCurrentStream(nil)
        queue.sync { lastSampleEnd = .invalid }
        timelineAnchor.reset(timelineStartTime: request.timelineStartTime)
        startupGate.reset()
        hasReportedActiveFailure = false
        includesRecorderUI = request.settings.includesRecorderUI
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
        recoverySegments = AudioRecoverySegmentWriter(.init(audioURL: request.url, timelineStartTime: request.timelineStartTime))

        if let prewarmedStream {
            self.prewarmedStream = nil
            setCurrentStream(prewarmedStream)
            CaptureLog.note("System audio recording \(request.url.lastPathComponent) from the monitoring stream")
            try prewarmedStream.attachAudioOutput(.init(output: self, sampleHandlerQueue: queue))
            stream = prewarmedStream
            try await waitForFirstAudioSample()
            return
        }

        try await startStream(filter: SystemAudioStreamConfiguration.contentFilter(request.pickedScreenFilter))
        CaptureLog.note("System audio recording \(request.url.lastPathComponent)")
        try await waitForFirstAudioSample()
    }

    private func startStream(filter: SCContentFilter) async throws {
        let configuration = SystemAudioStreamConfiguration.configuration(.init(
            streamName: "BlitzRecorder System Audio", includesRecorderUI: includesRecorderUI
        ))
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.attachAudioOutput(.init(output: self, sampleHandlerQueue: queue))
        try await stream.startCapture()
        setCurrentStream(stream)
        self.stream = stream
    }

    private func setCurrentStream(_ stream: (any SystemAudioStreaming)?) {
        currentStreamLock.withLock { currentStreamID = stream.map(ObjectIdentifier.init) }
    }

    private func isCurrent(_ stream: SCStream) -> Bool {
        currentStreamLock.withLock { currentStreamID == ObjectIdentifier(stream) }
    }

    func adoptMonitoringStream(_ stream: any SystemAudioStreaming) {
        prewarmedStream = stream
    }

    func pause() {
        writer?.pause()
        recoverySegments?.pause()
    }

    /// Starts a stream for the new screen source, then stops the old one, so sound continues without a gap.
    /// Retargeting the old stream is not enough: once its window closed it can accept a new filter and stay
    /// silent, and the monitoring stream adopted at start reports its end only to the level monitor.
    func update(filter pickedScreenFilter: SCContentFilter?) async throws {
        guard let previous = stream else { return }
        try await startStream(filter: SystemAudioStreamConfiguration.contentFilter(pickedScreenFilter))
        CaptureLog.note("System audio moved to a new stream for the new screen source")
        try? await previous.stopCapture()
    }

    func resume() {
        writer?.resume()
        recoverySegments?.resume()
    }

    func stop() async throws -> MediaWriterCompletion {
        completeStartup(.failure(RecorderError.systemAudioDidNotStart))
        let writerToFinish = writer
        writer = nil
        let segmentsToFinish = recoverySegments
        recoverySegments = nil
        await segmentsToFinish?.finish()
        setCurrentStream(nil)
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        if let prewarmedStream {
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
        guard type == .audio, sampleBuffer.isValid, isCurrent(stream) else {
            return
        }
        receiveAudioSample(sampleBuffer)
    }

    /// Drops a buffer that starts before the previous one ended, which happens for a moment when a new stream takes
    /// over: the writer rejects time going backwards and would fail the whole file.
    func receiveAudioSample(_ sampleBuffer: CMSampleBuffer) {
        let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastSampleEnd.isValid, start.isValid,
           CMTimeCompare(CMTimeAdd(start, Self.timeTolerance), lastSampleEnd) < 0 {
            return
        }
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        if start.isValid, duration.isValid {
            lastSampleEnd = CMTimeAdd(start, duration)
        }
        timelineAnchor.observeFirstSample(sampleBuffer)
        levelPublisher.publish(from: sampleBuffer)
        writer?.append(sampleBuffer)
        recoverySegments?.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isCurrent(stream) else { return }
        if ScreenSourceLost.matches(error), startupGate.hasProducedSample, !hasReportedActiveFailure {
            CaptureLog.note("System audio source closed; waiting for a new screen source: \(error.localizedDescription)")
            let failureHandler = failureHandler
            Task { @MainActor in failureHandler?(ScreenSourceLost()) }
            return
        }
        CaptureLog.note("System audio stream stopped: \(error.localizedDescription)")
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
