import AVFoundation
import Foundation

enum CaptureDeviceCatalog {
    static func connectedCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        .filter { $0.isConnected && !$0.isSuspended }
        .sorted {
            LocalCameraSessionConfiguration.cameraSortKey($0)
                < LocalCameraSessionConfiguration.cameraSortKey($1)
        }
    }

    static func localCameraOptions() -> [SourceOption] {
        connectedCameras().map { device in
            let kind: CameraSourceKind
            if device.deviceType == .deskViewCamera { kind = .deskView }
            else if device.isContinuityCamera { kind = .continuity }
            else if device.deviceType == .builtInWideAngleCamera { kind = .builtIn }
            else { kind = .external }
            return SourceOption(id: device.uniqueID, name: displayName(for: device), cameraKind: kind)
        }
    }

    static func displayName(for device: AVCaptureDevice) -> String {
        if device.isContinuityCamera {
            return "\(device.localizedName) (Continuity)"
        }
        if device.deviceType == .deskViewCamera {
            return "\(device.localizedName) (Desk View)"
        }
        return device.localizedName
    }

    static func microphoneOptions() -> [SourceOption] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.map { SourceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func microphoneName(selectedID: String?) -> String {
        if let selectedID, let device = AVCaptureDevice(uniqueID: selectedID) {
            return device.localizedName
        }
        if let device = AVCaptureDevice.default(for: .audio) {
            return device.localizedName
        }
        return "Default microphone"
    }
}
