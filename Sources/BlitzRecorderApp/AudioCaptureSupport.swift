import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

struct AudioLevelUpdateThrottle {
    static let minimumIntervalNanoseconds: UInt64 = 66_666_667

    private var lastUpdateNanoseconds: UInt64?

    mutating func shouldPublish(at nowNanoseconds: UInt64) -> Bool {
        guard let lastUpdateNanoseconds else {
            self.lastUpdateNanoseconds = nowNanoseconds
            return true
        }
        guard nowNanoseconds - lastUpdateNanoseconds >= Self.minimumIntervalNanoseconds else {
            return false
        }
        self.lastUpdateNanoseconds = nowNanoseconds
        return true
    }
}

final class AudioLevelPublisher: @unchecked Sendable {
    var levelHandler: ((Float) -> Void)?
    private var updateThrottle = AudioLevelUpdateThrottle()

    func publish(from sampleBuffer: CMSampleBuffer) {
        guard updateThrottle.shouldPublish(at: DispatchTime.now().uptimeNanoseconds),
              let level = AudioLevelMeter.level(from: sampleBuffer) else {
            return
        }

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
    static func contentFilter(_ pickedFilter: SCContentFilter?) throws -> SCContentFilter {
        guard let pickedFilter else {
            throw RecorderError.screenCapturePermissionRequired
        }
        return pickedFilter
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
