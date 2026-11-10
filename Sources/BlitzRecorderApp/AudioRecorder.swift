import AVFoundation
import CoreMedia
import Foundation

final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    AVCaptureFileOutputRecordingDelegate, @unchecked Sendable
{
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "blitzrecorder.microphone")
    private var fileOutput: AVCaptureAudioFileOutput?
    private var outputURL: URL?
    private var outputFileType: AVFileType = .m4a
    private var recordingResult: Result<MediaWriterCompletion, Error>?
    private var finishContinuation: CheckedContinuation<MediaWriterCompletion, Error>?
    private var didRequestRecording = false
    private var clockRateEstimator = CaptureClockRateEstimator()
    private var pauseController = AudioRecordingPauseController()
    private var normalizationFormat: SourceAudioFormat = .aac
    private var normalizationBitrate = 192_000
    private var pendingClockNormalization: AudioClockNormalizationRequest?
    private var hasEmittedSyncWarning = false
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }
    var failureHandler: ((Error) -> Void)?
    var syncWarningHandler: ((String) -> Void)?
    private let startupGate = AudioStartupGate(timeoutError: RecorderError.microphoneDidNotStart)
    private var timelineAnchor = RecordingTimelineAnchor()
    private var recoverySegments: AudioRecoverySegmentWriter?
    /// An extra microphone keeps what it recorded when its device goes away mid-take, instead of deleting the file.
    private let keepsRecordingOnFailure: Bool
    private var sessionObservers: [NSObjectProtocol] = []
    private var lastHealthNoteTime = 0.0
    private static let healthNoteSeconds = 60.0

    override convenience init() {
        self.init(keepsRecordingOnFailure: false)
    }

    init(keepsRecordingOnFailure: Bool) {
        self.keepsRecordingOnFailure = keepsRecordingOnFailure
        super.init()
        observeSession()
    }

    deinit {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private var fileName: String {
        outputURL?.lastPathComponent ?? "microphone"
    }

    private func observeSession() {
        let names: [Notification.Name] = [
            AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.wasInterruptedNotification,
            AVCaptureSession.interruptionEndedNotification,
            AVCaptureSession.didStopRunningNotification,
        ]
        sessionObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                let error = (note.userInfo?[AVCaptureSessionErrorKey] as? Error).map { ": \($0.localizedDescription)" } ?? ""
                self?.queue.async {
                    let recording = self?.fileOutput?.isRecording == true
                    CaptureLog.note("Microphone session \(name.rawValue)\(error), file output recording: \(recording)")
                }
            }
        }
    }

    var recordingTimelineOffset: CMTime {
        queue.sync { timelineAnchor.offset }
    }

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) async throws {
        try queue.sync {
            guard let device = MicrophoneDeviceSelection.selectedMicrophone(settings: settings) else {
                throw RecorderError.microphoneUnavailable
            }

            var didBeginConfiguration = false
            do {
                try? FileManager.default.removeItem(at: url)
                self.outputURL = url
                outputFileType = settings.effectiveSourceAudioFormat.avFileType
                recordingResult = nil
                finishContinuation = nil
                didRequestRecording = false
                clockRateEstimator.reset()
                pauseController = AudioRecordingPauseController()
                normalizationFormat = settings.effectiveSourceAudioFormat
                normalizationBitrate = settings.finalAudioBitrate
                pendingClockNormalization = nil
                hasEmittedSyncWarning = false
                timelineAnchor.reset(timelineStartTime: timelineStartTime)
                lastHealthNoteTime = 0
                recoverySegments = AudioRecoverySegmentWriter(.init(audioURL: url, timelineStartTime: timelineStartTime))
                startupGate.reset()

                session.beginConfiguration()
                didBeginConfiguration = true
                AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: session)

                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    throw RecorderError.microphoneUnavailable
                }
                session.addInput(input)

                let output = AVCaptureAudioFileOutput()
                output.audioSettings = Self.audioSettings(
                    AudioFileOutputSettingsRequest(
                        device: device,
                        settings: settings
                    )
                )
                CaptureLog.note(
                    "Microphone \(device.localizedName) [\(device.uniqueID)] recording \(url.path), "
                        + "device format \(device.activeFormat.formatDescription), "
                        + "file \(outputFileType.rawValue) \(output.audioSettings ?? [:])"
                )
                guard session.canAddOutput(output) else {
                    throw RecorderError.writerNotReady
                }
                session.addOutput(output)
                fileOutput = output

                let meterOutput = AVCaptureAudioDataOutput()
                meterOutput.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(meterOutput) else {
                    meterOutput.setSampleBufferDelegate(nil, queue: nil)
                    throw RecorderError.writerNotReady
                }
                session.addOutput(meterOutput)

                session.commitConfiguration()
                didBeginConfiguration = false
                if !session.isRunning {
                    session.startRunning()
                }
                didRequestRecording = true
                output.startRecording(
                    to: url,
                    outputFileType: outputFileType,
                    recordingDelegate: self
                )
            } catch {
                fileOutput = nil
                outputURL = nil
                if didBeginConfiguration {
                    AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: session)
                    session.commitConfiguration()
                }
                throw error
            }
        }
        try await waitForFirstAudioSample()
    }

    func pause() {
        queue.async {
            guard let output = self.fileOutput, self.pauseController.pause(output) else { return }
            CaptureLog.note("\(self.fileName): paused at \(output.recordedDuration.seconds) s")
            self.clockRateEstimator.pause()
            self.recoverySegments?.pause()
        }
    }

    func resume() {
        queue.async {
            guard let output = self.fileOutput, self.pauseController.resume(output) else { return }
            CaptureLog.note("\(self.fileName): resumed")
            self.clockRateEstimator.resume()
            self.recoverySegments?.resume()
        }
    }

    func switchMicrophone(to deviceID: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let device = MicrophoneDeviceSelection.microphone(id: deviceID),
                          self.fileOutput?.isRecording == true else {
                        throw RecorderError.microphoneUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    let previousInputs = self.session.inputs
                    self.session.beginConfiguration()
                    previousInputs.forEach { self.session.removeInput($0) }
                    guard self.session.canAddInput(input) else {
                        previousInputs.filter { self.session.canAddInput($0) }.forEach {
                            self.session.addInput($0)
                        }
                        self.session.commitConfiguration()
                        throw RecorderError.microphoneUnavailable
                    }
                    self.session.addInput(input)
                    self.session.commitConfiguration()
                    CaptureLog.note("\(self.fileName): switched to \(device.localizedName) [\(device.uniqueID)]")
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async throws -> MediaWriterCompletion {
        let fileResult: Result<MediaWriterCompletion, Error>
        do {
            fileResult = .success(try await stopFileOutput())
        } catch {
            fileResult = .failure(error)
        }
        await finishRecoverySegments()
        let (completion, rebuilt) = try await checkedAgainstBackup(fileResult)
        queue.sync {
            guard !rebuilt,
                  completion.wroteMedia,
                  let url = completion.url,
                  let measurement = clockRateEstimator.measurement else {
                pendingClockNormalization = nil
                return
            }
            pendingClockNormalization = AudioClockNormalizationRequest(
                url: url,
                format: normalizationFormat,
                bitrate: normalizationBitrate,
                measurement: measurement
            )
        }
        await tearDownSession()
        levelPublisher.reset()
        return completion
    }

    /// A file the output called finished can still be a few seconds of a long take, so it is checked against the
    /// backup segments, which are deleted once the take is saved. A rebuilt file is already placed by the session
    /// clock, so it skips clock correction.
    private func checkedAgainstBackup(
        _ fileResult: Result<MediaWriterCompletion, Error>
    ) async throws -> (MediaWriterCompletion, Bool) {
        let request = queue.sync { outputURL.map {
            AudioBackupCheck.Request(
                audioURL: $0, format: normalizationFormat, stereoBitrate: normalizationBitrate,
                timelineStart: timelineAnchor.offset.seconds
            )
        } }
        if case .failure(let error) = fileResult {
            CaptureLog.note("\(request?.audioURL.lastPathComponent ?? "microphone"): file output failed: \(error)")
        }
        guard let request, await AudioBackupCheck.verify(request) == .rebuilt else {
            return (try fileResult.get(), false)
        }
        return (.wrote(request.audioURL), true)
    }

    private func finishRecoverySegments() async {
        let segments = queue.sync {
            defer { recoverySegments = nil }
            return recoverySegments
        }
        await segments?.finish()
    }

    func finalizeSynchronization() async throws {
        try await finalizeSynchronization(.init(onProgress: { _ in }))
    }

    func finalizeSynchronization(_ progress: AudioSynchronizationProgress) async throws {
        guard var request = queue.sync(execute: {
            let request = pendingClockNormalization
            pendingClockNormalization = nil
            return request
        }) else {
            progress.onProgress(1)
            return
        }
        request.onProgress = progress.onProgress
        let result = try await AudioClockNormalizer.normalize(request)
        if result.didCorrect {
            NSLog(
                "Microphone clock corrected by %.3fs at rate %.9f",
                result.accumulatedDrift.seconds,
                request.measurement.masterTimePerSourceTime
            )
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        queue.async {
            self.levelPublisher.publish(from: sampleBuffer)
            if self.fileOutput?.isRecording == true, !self.pauseController.isPaused {
                self.recoverySegments?.append(sampleBuffer)
            }
            if self.fileOutput?.isRecording == true,
               !self.pauseController.isPaused,
               let sampleDuration = Self.sampleDuration(of: sampleBuffer) {
                self.clockRateEstimator.observe(.init(
                    sampleDuration: sampleDuration,
                    masterTime: CMClockGetTime(CMClockGetHostTimeClock())
                ))
                self.emitSyncWarningIfNeeded()
                self.noteHealthIfDue()
            }
            self.timelineAnchor.observeFirstSample(sampleBuffer)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        queue.async {
            CaptureLog.note("\(fileURL.lastPathComponent): file output started")
            self.completeStartup(.success(()))
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        queue.async {
            let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path))?[.size] as? NSNumber
            CaptureLog.note(
                "\(outputFileURL.lastPathComponent): file output finished, \(size?.int64Value ?? 0) bytes, "
                    + "\(output.recordedDuration.seconds) s, error: \(error.map { "\($0)" } ?? "none")"
            )
            let result: Result<MediaWriterCompletion, Error>
            var keptAfterError: Error?
            if let error, self.keepsRecordingOnFailure, Self.hasRecordedAudio(at: outputFileURL) {
                keptAfterError = error
                result = .success(.wrote(outputFileURL))
            } else if let error {
                try? FileManager.default.removeItem(at: outputFileURL)
                result = .failure(error)
            } else if Self.hasRecordedAudio(at: outputFileURL) {
                result = .success(.wrote(outputFileURL))
            } else {
                try? FileManager.default.removeItem(at: outputFileURL)
                result = .success(.empty(outputFileURL))
            }
            self.recordingResult = result
            self.completeStartup(result.map { _ in () })
            if let continuation = self.finishContinuation {
                self.finishContinuation = nil
                continuation.resume(with: result)
            } else if case .failure(let error) = result, self.startupGate.hasProducedSample {
                self.failureHandler?(error)
            } else if let keptAfterError, self.startupGate.hasProducedSample {
                self.failureHandler?(keptAfterError)
            }
        }
    }

    private func stopFileOutput() async throws -> MediaWriterCompletion {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let recordingResult = self.recordingResult {
                    continuation.resume(with: recordingResult)
                    return
                }
                guard let output = self.fileOutput,
                      output.isRecording else {
                    continuation.resume(returning: .empty(self.outputURL))
                    return
                }
                self.finishContinuation = continuation
                self.clockRateEstimator.pause()
                output.stopRecording()
            }
        }
    }

    private func tearDownSession() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.completeStartup(.failure(RecorderError.microphoneDidNotStart))
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.session.beginConfiguration()
                AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: self.session)
                self.session.commitConfiguration()
                self.fileOutput = nil
                self.outputURL = nil
                self.didRequestRecording = false
                continuation.resume()
            }
        }
    }

    private func waitForFirstAudioSample() async throws {
        try await startupGate.wait(on: queue)
    }

    private func completeStartup(_ result: Result<Void, Error>) {
        startupGate.complete(result)
    }

    private static func audioSettings(_ request: AudioFileOutputSettingsRequest) -> [String: Any] {
        let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
            request.device.activeFormat.formatDescription
        )?.pointee
        let sampleRate = streamDescription?.mSampleRate ?? 48_000
        let channelCount = max(1, min(2, Int(streamDescription?.mChannelsPerFrame ?? 2)))
        return request.settings.effectiveSourceAudioFormat.outputSettings(.init(
            sampleRate: sampleRate, channelCount: channelCount, stereoBitrate: request.settings.finalAudioBitrate
        ))
    }

    private static func hasRecordedAudio(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value > 0
    }

    private static func sampleDuration(of sampleBuffer: CMSampleBuffer) -> CMTime? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
              )?.pointee,
              streamDescription.mSampleRate > 0 else {
            return nil
        }
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return nil }
        return CMTime(
            seconds: Double(sampleCount) / streamDescription.mSampleRate,
            preferredTimescale: 1_000_000_000
        )
    }

    /// Logs what the file output reports having written, so a file that stops growing mid-take shows when it stopped.
    private func noteHealthIfDue() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHealthNoteTime >= Self.healthNoteSeconds, let output = fileOutput else { return }
        lastHealthNoteTime = now
        let size = outputURL.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.size] as? NSNumber }
        CaptureLog.note(
            "\(fileName): recording \(output.recordedDuration.seconds) s, output reports \(output.recordedFileSize) bytes, "
                + "file on disk \(size?.int64Value ?? 0) bytes"
        )
    }

    private func emitSyncWarningIfNeeded() {
        guard !hasEmittedSyncWarning,
              let measurement = clockRateEstimator.measurement,
              measurement.sourceDuration.seconds >= 30 else {
            return
        }
        let rate = measurement.masterTimePerSourceTime
        guard rate < 0.98 || rate > 1.02 else { return }
        hasEmittedSyncWarning = true
        syncWarningHandler?("Microphone synchronization is unstable. Recording continues with automatic correction.")
    }
}

private struct AudioFileOutputSettingsRequest {
    let device: AVCaptureDevice
    let settings: RecordingSettings
}

protocol AudioFilePauseRecording: AnyObject {
    var isRecording: Bool { get }
    func pauseRecording()
    func resumeRecording()
}

extension AVCaptureAudioFileOutput: AudioFilePauseRecording {}

struct AudioRecordingPauseController {
    private(set) var isPaused = false

    mutating func pause(_ output: any AudioFilePauseRecording) -> Bool {
        guard !isPaused, output.isRecording else { return false }
        isPaused = true
        output.pauseRecording()
        return true
    }

    mutating func resume(_ output: any AudioFilePauseRecording) -> Bool {
        guard isPaused else { return false }
        isPaused = false
        output.resumeRecording()
        return true
    }
}
