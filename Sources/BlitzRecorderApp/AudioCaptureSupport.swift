import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class AudioLevelPublisher: @unchecked Sendable {
    var levelHandler: ((Float) -> Void)?
    private var lastLevelTime = DispatchTime(uptimeNanoseconds: 0)

    func publish(from sampleBuffer: CMSampleBuffer) {
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

    func reset() {
        Task { @MainActor [levelHandler] in
            levelHandler?(0)
        }
    }
}

enum MicrophoneDeviceSelection {
    static func selectedMicrophone(settings: RecordingSettings) -> AVCaptureDevice? {
        if let selectedMicrophoneID = settings.selectedMicrophoneID,
           let device = AVCaptureDevice(uniqueID: selectedMicrophoneID) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }
}

enum AudioCaptureSessionCleanup {
    static func detachAudioOutputs(from session: AVCaptureSession) {
        session.outputs
            .compactMap { $0 as? AVCaptureAudioDataOutput }
            .forEach {
                $0.setSampleBufferDelegate(nil, queue: nil)
                session.removeOutput($0)
            }
    }

    static func detachAudioOutputsAndRemoveAll(from session: AVCaptureSession) {
        detachAudioOutputs(from: session)
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
    }
}

enum SystemAudioStreamConfiguration {
    static func contentFilter(settings: RecordingSettings) async throws -> SCContentFilter {
        let content = try await SCShareableContent.current
        guard let display = ScreenCaptureGeometry.display(from: content.displays, settings: settings) else {
            throw RecorderError.noDisplay
        }

        let ownProcess = getpid()
        let excludedApplications = content.applications.filter { $0.processID == ownProcess }
        return SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
    }

    static func configuration(streamName: String) -> SCStreamConfiguration {
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
        configuration.streamName = streamName
        return configuration
    }
}
