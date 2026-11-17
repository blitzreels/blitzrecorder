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

/// The level monitor's running stream, handed to the recorder so a take starts without a new stream.
struct SystemAudioMonitoringStream {
    let stream: any SystemAudioStreaming
    let scope: SystemAudioScope
}

struct SystemAudioUpdateRequest {
    let settings: RecordingSettings
    let pickedScreenFilter: SCContentFilter?
}

private struct BackupCheckTarget {
    let audioURL: URL
    let format: SourceAudioFormat
    let stereoBitrate: Int
}

final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "blitzrecorder.system-audio")
    private var stream: (any SystemAudioStreaming)?
    private var prewarmedStream: SystemAudioMonitoringStream?
    private var scope: SystemAudioScope?
    private var writer: AudioSampleFileWriter?
    private var recoverySegments: AudioRecoverySegmentWriter?
    private var backupCheck: BackupCheckTarget?
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
        let scope = SystemAudioScope(settings: request.settings)
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
        backupCheck = .init(
            audioURL: request.url,
            format: request.settings.effectiveSourceAudioFormat,
            stereoBitrate: request.settings.finalAudioBitrate
        )

        if let prewarmed = prewarmedStream {
            prewarmedStream = nil
            if prewarmed.scope == scope {
                setCurrentStream(prewarmed.stream)
                CaptureLog.note("System audio recording \(request.url.lastPathComponent) from the monitoring stream")
                try prewarmed.stream.attachAudioOutput(.init(output: self, sampleHandlerQueue: queue))
                stream = prewarmed.stream
                self.scope = scope
                try await waitForFirstAudioSample()
                return
            }
            try? await prewarmed.stream.stopCapture()
        }

        try await startStream(.init(scope: scope, pickedScreenFilter: request.pickedScreenFilter))
        CaptureLog.note("System audio recording \(request.url.lastPathComponent) (\(scope.logDescription))")
        try await waitForFirstAudioSample()
    }

    private func startStream(_ request: SystemAudioStreamConfiguration.FilterRequest) async throws {
        let filter = try await SystemAudioStreamConfiguration.contentFilter(request)
        let configuration = SystemAudioStreamConfiguration.configuration(.init(
            streamName: "BlitzRecorder System Audio", includesRecorderUI: request.scope.includesRecorderUI
        ))
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.attachAudioOutput(.init(output: self, sampleHandlerQueue: queue))
        try await stream.startCapture()
        setCurrentStream(stream)
        self.stream = stream
        scope = request.scope
    }

    private func setCurrentStream(_ stream: (any SystemAudioStreaming)?) {
        currentStreamLock.withLock { currentStreamID = stream.map(ObjectIdentifier.init) }
    }

    private func isCurrent(_ stream: SCStream) -> Bool {
        currentStreamLock.withLock { currentStreamID == ObjectIdentifier(stream) }
    }

    func adoptMonitoringStream(_ monitoring: SystemAudioMonitoringStream) {
        prewarmedStream = monitoring
    }

    func pause() {
        writer?.pause()
        recoverySegments?.pause()
    }

    /// Keeps the running stream when what it hears is unchanged, which is every switch between displays and
    /// windows: a new stream can take a second or more to start, and the microphone has stalled while it did.
    /// When the scope changes (an app source, or showing the recorder's own sound), starts a stream for it, then
    /// stops the old one, so sound continues without a gap. Retargeting the old stream is not enough: once its
    /// window closed it can accept a new filter and stay silent.
    func update(_ request: SystemAudioUpdateRequest) async throws {
        guard let previous = stream else { return }
        let newScope = SystemAudioScope(settings: request.settings)
        if newScope == scope {
            CaptureLog.note("System audio kept its stream for the new screen source (\(newScope.logDescription))")
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        try await startStream(.init(scope: newScope, pickedScreenFilter: request.pickedScreenFilter))
        let startedNew = ProcessInfo.processInfo.systemUptime
        try? await previous.stopCapture()
        if let target = backupCheck {
            TakeSyncJournal.record(.init(
                trackURL: target.audioURL, kind: .systemAudioRestarted, at: nil,
                seconds: startedNew - started, detail: newScope.logDescription
            ))
        }
        CaptureLog.note(String(
            format: "System audio moved to a new stream (%@; new stream started in %.3f s, old one stopped in %.3f s)",
            newScope.logDescription, startedNew - started, ProcessInfo.processInfo.systemUptime - startedNew
        ))
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
        let backup = await segmentsToFinish?.finish() ?? .init()
        setCurrentStream(nil)
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        scope = nil
        if let prewarmedStream {
            try? await prewarmedStream.stream.stopCapture()
        }
        prewarmedStream = nil
        let fileResult: Result<MediaWriterCompletion, Error>
        do {
            fileResult = .success(try await writerToFinish?.finish() ?? .empty())
        } catch {
            fileResult = .failure(error)
        }
        let completion = try await checkedAgainstBackup(.init(fileResult: fileResult, backup: backup))
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

    private struct BackupCheckRequest {
        let fileResult: Result<MediaWriterCompletion, Error>
        let backup: AudioRecoverySegmentWriter.Report
    }

    /// The writer joins the samples on both sides of a stall like the microphone file output does, so the file is
    /// built from the timestamped backup the same way.
    private func checkedAgainstBackup(_ check: BackupCheckRequest) async throws -> MediaWriterCompletion {
        guard let target = backupCheck else { return try check.fileResult.get() }
        backupCheck = nil
        if case .failure(let error) = check.fileResult {
            CaptureLog.note("\(target.audioURL.lastPathComponent): writer failed: \(error.localizedDescription)")
        }
        let request = AudioBackupCheck.Request(
            audioURL: target.audioURL, format: target.format, stereoBitrate: target.stereoBitrate,
            timelineStart: queue.sync { timelineAnchor.offset.seconds }, backup: check.backup
        )
        let outcome = await AudioBackupCheck.verify(request)
        return outcome.replacedFile ? .wrote(target.audioURL) : try check.fileResult.get()
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
