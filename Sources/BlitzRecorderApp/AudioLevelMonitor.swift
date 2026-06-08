import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class MicrophoneLevelMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "blitzrecorder.microphone-monitor")
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }

    func start(settings: RecordingSettings) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.microphoneUnavailable
        }
        guard let device = MicrophoneDeviceSelection.selectedMicrophone(settings: settings) else {
            throw RecorderError.microphoneUnavailable
        }

        session.beginConfiguration()
        AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: session)

        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        session.commitConfiguration()
        queue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        session.stopRunning()
        session.beginConfiguration()
        AudioCaptureSessionCleanup.detachAudioOutputsAndRemoveAll(from: session)
        session.commitConfiguration()
        levelPublisher.reset()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        levelPublisher.publish(from: sampleBuffer)
    }
}

final class SystemAudioLevelMonitor: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "blitzrecorder.system-audio-monitor")
    private var stream: SCStream?
    private let levelPublisher = AudioLevelPublisher()
    var levelHandler: ((Float) -> Void)? {
        get { levelPublisher.levelHandler }
        set { levelPublisher.levelHandler = newValue }
    }

    func start(settings: RecordingSettings) async throws {
        try await stop()

        let filter = try await SystemAudioStreamConfiguration.contentFilter(settings: settings)
        let configuration = SystemAudioStreamConfiguration.configuration(streamName: "BlitzRecorder System Audio Monitor")
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        levelPublisher.reset()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else {
            return
        }
        levelPublisher.publish(from: sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("System audio monitor stopped: \(error.localizedDescription)")
    }
}
