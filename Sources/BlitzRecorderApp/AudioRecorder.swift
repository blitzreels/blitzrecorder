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

    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime? = nil) throws {
        guard let device = MicrophoneDeviceSelection.selectedMicrophone(settings: settings) else {
            throw RecorderError.microphoneUnavailable
        }

        writer = try AudioSampleFileWriter(url: url, timelineStartTime: timelineStartTime)

        session.beginConfiguration()
        AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: session)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.microphoneUnavailable
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw RecorderError.writerNotReady
        }
        session.addOutput(output)

        session.commitConfiguration()
        queue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
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
    }

    private func tearDownSession() async {
        await withCheckedContinuation { continuation in
            queue.async {
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
}
