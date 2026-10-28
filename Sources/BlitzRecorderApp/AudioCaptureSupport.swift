import AVFoundation
import BlitzRecorderCore
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
           let device = microphone(id: selectedMicrophoneID) {
            return device
        }
        return fallbackMicrophone(.init(settings: settings, excludedIDs: []))
    }

    /// BlitzRecorder Camera records with the iPhone's own camera and microphone, so the Mac must not take that
    /// iPhone's microphone through Continuity: iOS hands the iPhone to Continuity and the take on the iPhone stops.
    static func usesIPhoneCompanion(_ settings: RecordingSettings) -> Bool {
        settings.enabledSources.contains(.camera) && RemoteCameraProviderID.isRemote(settings.selectedCameraID)
    }

    /// The microphone a recording would use takes the iPhone away from BlitzRecorder Camera.
    static func conflictsWithIPhoneCompanion(settings: RecordingSettings) -> Bool {
        guard usesIPhoneCompanion(settings), settings.enabledSources.contains(.microphone),
              let device = selectedMicrophone(settings: settings) else { return false }
        return isContinuityMicrophone(device)
    }

    /// The preferred microphone is saved but not connected, so a recording would use another input.
    static func preferredIsMissing(settings: RecordingSettings) -> Bool {
        guard let id = settings.selectedMicrophoneID else { return false }
        return microphone(id: id) == nil
    }

    static func preferredName(id: String?) -> String? {
        id.flatMap { AVCaptureDevice(uniqueID: $0)?.localizedName }
    }

    static func microphone(id: String) -> AVCaptureDevice? {
        guard let device = AVCaptureDevice(uniqueID: id),
              device.isConnected,
              !device.isSuspended,
              device.hasMediaType(.audio) else { return nil }
        return device
    }

    struct FallbackRequest {
        let settings: RecordingSettings
        let excludedIDs: Set<String>
    }

    /// The microphone used when none is picked or the picked one is gone. While BlitzRecorder Camera is the camera
    /// it is never an iPhone microphone reached through Continuity: macOS makes that the default input on Macs
    /// without a microphone, and using it stopped the iPhone's take about once a minute.
    static func fallbackMicrophone(_ request: FallbackRequest) -> AVCaptureDevice? {
        let avoidsContinuity = usesIPhoneCompanion(request.settings)
        func usable(_ device: AVCaptureDevice) -> Bool {
            !request.excludedIDs.contains(device.uniqueID) && device.isConnected && !device.isSuspended
                && !(avoidsContinuity && isContinuityMicrophone(device))
        }
        if let device = AVCaptureDevice.default(for: .audio), usable(device) {
            return device
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.first(where: usable)
    }

    /// Core Audio's Continuity Capture transports, wired ('ccwd') and wireless ('ccwl').
    static func isContinuityMicrophone(_ device: AVCaptureDevice) -> Bool {
        [0x6363_7764, 0x6363_776C].contains(device.transportType)
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

    struct ConfigurationRequest {
        let streamName: String
        let includesRecorderUI: Bool
    }

    static func configuration(_ request: ConfigurationRequest) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 2
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = !request.includesRecorderUI
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.streamName = request.streamName
        return configuration
    }
}
