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
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var hasProducedStartupSample = false
    private var timelineStartTime: CMTime?
    private var firstSampleTime: CMTime?

    var recordingTimelineOffset: CMTime {
        queue.sync {
            guard let timelineStartTime,
                  let firstSampleTime else { return .zero }
            let offset = CMTimeSubtract(firstSampleTime, timelineStartTime)
            guard offset.isValid,
                  offset.seconds.isFinite,
                  CMTimeCompare(offset, .zero) > 0 else { return .zero }
            return CMTimeConvertScale(offset, timescale: 600, method: .roundHalfAwayFromZero)
        }
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
                normalizationFormat = settings.effectiveSourceAudioFormat
                normalizationBitrate = settings.finalAudioBitrate
                pendingClockNormalization = nil
                hasEmittedSyncWarning = false
                self.timelineStartTime = timelineStartTime
                firstSampleTime = nil
                hasProducedStartupSample = false

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
            guard self.fileOutput?.isRecording == true else { return }
            self.fileOutput?.pauseRecording()
            self.clockRateEstimator.pause()
        }
    }

    func resume() {
        queue.async {
            guard self.fileOutput?.isRecordingPaused == true else { return }
            self.fileOutput?.resumeRecording()
            self.clockRateEstimator.resume()
        }
    }

    func stop() async throws -> MediaWriterCompletion {
        let completion = try await stopFileOutput()
        queue.sync {
            guard completion.wroteMedia,
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

    func finalizeSynchronization() async throws {
        guard let request = queue.sync(execute: {
            let request = pendingClockNormalization
            pendingClockNormalization = nil
            return request
        }) else {
            return
        }
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
            if self.fileOutput?.isRecording == true,
               self.fileOutput?.isRecordingPaused == false,
               let sampleDuration = Self.sampleDuration(of: sampleBuffer) {
                self.clockRateEstimator.observe(.init(
                    sampleDuration: sampleDuration,
                    masterTime: CMClockGetTime(CMClockGetHostTimeClock())
                ))
                self.emitSyncWarningIfNeeded()
            }
            if self.firstSampleTime == nil {
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if presentationTime.isValid {
                    self.firstSampleTime = presentationTime
                }
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        queue.async {
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
            let result: Result<MediaWriterCompletion, Error>
            if let error {
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
            } else if case .failure(let error) = result, self.hasProducedStartupSample {
                self.failureHandler?(error)
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
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.hasProducedStartupSample {
                    continuation.resume()
                    return
                }
                self.startupContinuation = continuation
                self.startupTimeoutTask?.cancel()
                self.startupTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.queue.async {
                        self?.completeStartup(.failure(RecorderError.microphoneDidNotStart))
                    }
                }
            }
        }
    }

    private func completeStartup(_ result: Result<Void, Error>) {
        if case .success = result {
            hasProducedStartupSample = true
        }
        guard let continuation = startupContinuation else { return }
        startupContinuation = nil
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        continuation.resume(with: result)
    }

    private static func audioSettings(_ request: AudioFileOutputSettingsRequest) -> [String: Any] {
        let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
            request.device.activeFormat.formatDescription
        )?.pointee
        let sampleRate = streamDescription?.mSampleRate ?? 48_000
        let channelCount = max(1, min(2, Int(streamDescription?.mChannelsPerFrame ?? 2)))
        if request.settings.effectiveSourceAudioFormat.isLossless {
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1
                ? request.settings.finalAudioBitrate / 2
                : request.settings.finalAudioBitrate
        ]
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
