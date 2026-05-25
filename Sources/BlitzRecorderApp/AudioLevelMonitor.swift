import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class MicrophoneLevelMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "blitzrecorder.microphone-monitor")
    private var lastLevelTime = DispatchTime(uptimeNanoseconds: 0)
    var levelHandler: ((Float) -> Void)?

    func start(settings: RecordingSettings) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.microphoneUnavailable
        }
        guard let device = selectedMicrophone(settings: settings) else {
            throw RecorderError.microphoneUnavailable
        }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

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
        Task { @MainActor [levelHandler] in
            levelHandler?(0)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        publishLevel(from: sampleBuffer)
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

final class SystemAudioLevelMonitor: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "blitzrecorder.system-audio-monitor")
    private var stream: SCStream?
    private var lastLevelTime = DispatchTime(uptimeNanoseconds: 0)
    var levelHandler: ((Float) -> Void)?

    func start(settings: RecordingSettings) async throws {
        try await stop()

        let content = try await SCShareableContent.current
        guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
            throw RecorderError.noDisplay
        }

        let ownProcess = getpid()
        let excludedApplications = content.applications.filter { $0.processID == ownProcess }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 2
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.streamName = "BlitzRecorder System Audio Monitor"

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
        Task { @MainActor [levelHandler] in
            levelHandler?(0)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else {
            return
        }
        publishLevel(from: sampleBuffer)
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

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("System audio monitor stopped: \(error.localizedDescription)")
    }
}
