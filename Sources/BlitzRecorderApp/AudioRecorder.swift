import AVFoundation
import CoreMedia
import Foundation

final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "blitzrecorder.microphone")
    private var writer: AudioSampleFileWriter?
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }
    private var startupContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var hasProducedStartupSample = false

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) async throws {
        try queue.sync {
            guard let device = MicrophoneDeviceSelection.selectedMicrophone(settings: settings) else {
                throw RecorderError.microphoneUnavailable
            }

            var didBeginConfiguration = false
            do {
                writer = try AudioSampleFileWriter(
                    url: url,
                    timelineStartTime: timelineStartTime,
                    stereoBitrate: settings.finalAudioBitrate,
                    format: settings.effectiveSourceAudioFormat
                )
                hasProducedStartupSample = false

                session.beginConfiguration()
                didBeginConfiguration = true
                AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: session)

                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    throw RecorderError.microphoneUnavailable
                }
                session.addInput(input)

                let output = AVCaptureAudioDataOutput()
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddOutput(output) else {
                    output.setSampleBufferDelegate(nil, queue: nil)
                    throw RecorderError.writerNotReady
                }
                session.addOutput(output)

                session.commitConfiguration()
                didBeginConfiguration = false
                if !session.isRunning {
                    session.startRunning()
                }
            } catch {
                writer = nil
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
        writer?.pause()
    }

    func resume() {
        writer?.resume()
    }

    func stop() async throws -> MediaWriterCompletion {
        let writerToFinish = await withCheckedContinuation { continuation in
            queue.async {
                self.session.beginConfiguration()
                AudioCaptureSessionCleanup.detachAudioOutputs(from: self.session)
                self.session.commitConfiguration()
                let writer = self.writer
                self.writer = nil
                continuation.resume(returning: writer)
            }
        }
        do {
            let completion = try await writerToFinish?.finish() ?? .empty()
            await tearDownSession()
            levelPublisher.reset()
            return completion
        } catch {
            await tearDownSession()
            levelPublisher.reset()
            throw error
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        levelPublisher.publish(from: sampleBuffer)
        writer?.append(sampleBuffer)
        completeStartup(.success(()))
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

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
