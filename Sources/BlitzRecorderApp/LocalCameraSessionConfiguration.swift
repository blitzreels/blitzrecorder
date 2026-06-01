import AVFoundation
import CoreMedia
import Foundation

enum LocalCameraSessionConfiguration {
    static func configurePreset(on session: AVCaptureSession) {
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }
    }

    static func selectedCamera(settings: RecordingSettings, fallbackToDefault: Bool = true) -> AVCaptureDevice? {
        if let selectedCameraID = settings.selectedCameraID,
           let device = AVCaptureDevice(uniqueID: selectedCameraID),
           device.isConnected,
           !device.isSuspended {
            return device
        }

        if let discovered = discoveredCameras().first {
            return discovered
        }

        guard fallbackToDefault else { return nil }
        let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard fallback?.isConnected == true, fallback?.isSuspended == false else {
            return nil
        }
        return fallback
    }

    static func configure(device: AVCaptureDevice, fps: Int, logPrefix: String) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            let compatibleFormats = device.formats.filter { format in
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) }
            }
            let fourKFormats = compatibleFormats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width <= 3840 && dimensions.height <= 2160
            }
            let candidates = fourKFormats.isEmpty ? compatibleFormats : fourKFormats

            if let format = candidates.sorted(by: { cameraFormatSortKey($0) < cameraFormatSortKey($1) }).first {
                device.activeFormat = format
            }

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            if shouldForceFrameDuration(for: device),
               device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(fps) }) {
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            }
        } catch {
            NSLog("\(logPrefix) camera configuration failed: \(error.localizedDescription)")
        }
    }

    static func cameraSortKey(_ device: AVCaptureDevice) -> String {
        let priority: String
        if device.isContinuityCamera {
            priority = "0"
        } else if device.deviceType == .external {
            priority = "1"
        } else if device.deviceType == .deskViewCamera {
            priority = "2"
        } else {
            priority = "3"
        }
        return "\(priority)-\(device.localizedName)"
    }

    static func cameraFormatSortKey(_ format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = max(1, Int(dimensions.width))
        let height = max(1, Int(dimensions.height))
        let aspect = Double(width) / Double(height)
        let aspectPenalty = Int((abs(aspect - Double(SceneLayout.cameraAspectRatio)) * 10_000).rounded())
        let areaRank = 10_000_000 - min(9_999_999, width * height)
        return String(format: "%06d-%08d", aspectPenalty, areaRank)
    }

    private static func discoveredCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .deskViewCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        .filter { $0.isConnected && !$0.isSuspended }
        .sorted { cameraSortKey($0) < cameraSortKey($1) }
    }

    private static func shouldForceFrameDuration(for device: AVCaptureDevice) -> Bool {
        device.deviceType == .builtInWideAngleCamera
    }
}
