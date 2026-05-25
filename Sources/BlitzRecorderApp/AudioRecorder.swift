import AVFoundation
import CoreMedia
import Foundation

final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "blitzrecorder.microphone")
    private var writer: AudioSampleFileWriter?
    var levelHandler: ((Float) -> Void)?
    private var lastLevelTime = DispatchTime(uptimeNanoseconds: 0)

    func start(url: URL, settings: RecordingSettings) throws {
        guard let device = selectedMicrophone(settings: settings) else {
            throw RecorderError.microphoneUnavailable
        }

        writer = try AudioSampleFileWriter(url: url)

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

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
        session.stopRunning()
        let completion = try await writer?.finish() ?? .empty()
        writer = nil
        Task { @MainActor [levelHandler] in
            levelHandler?(0)
        }
        return completion
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
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

    private func selectedMicrophone(settings: RecordingSettings) -> AVCaptureDevice? {
        if let selectedMicrophoneID = settings.selectedMicrophoneID,
           let device = AVCaptureDevice(uniqueID: selectedMicrophoneID) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }
}
