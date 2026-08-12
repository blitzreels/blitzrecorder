import AVFoundation
import CoreMedia
import Foundation

struct LocalCameraDeviceConfigurationRequest {
    let device: AVCaptureDevice
    let fps: Int
    let logPrefix: String
    let cameraIsRunningSomewhere: Bool
}

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

        let fallback = AVCaptureDevice.default(for: .video)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
        if fallbackToDefault,
           fallback?.isConnected == true,
           fallback?.isSuspended == false {
            return fallback
        }

        return discoveredCameras().first
    }

    static func configure(_ request: LocalCameraDeviceConfigurationRequest) {
        guard !request.cameraIsRunningSomewhere else { return }
        do {
            try request.device.lockForConfiguration()
            defer { request.device.unlockForConfiguration() }

            let compatibleFormats = request.device.formats.filter { format in
                format.videoSupportedFrameRateRanges.contains {
                    $0.maxFrameRate >= Double(request.fps)
                }
            }
            let fourKFormats = compatibleFormats.filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return dimensions.width <= 3840 && dimensions.height <= 2160
            }
            let candidates = fourKFormats.isEmpty ? compatibleFormats : fourKFormats

            if let format = candidates.sorted(by: { cameraFormatSortKey($0) < cameraFormatSortKey($1) }).first {
                request.device.activeFormat = format
            }

            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(request.fps))
            if shouldForceFrameDuration(for: request.device),
               request.device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                   $0.maxFrameRate >= Double(request.fps)
               }) {
                request.device.activeVideoMinFrameDuration = frameDuration
                request.device.activeVideoMaxFrameDuration = frameDuration
            }
        } catch {
            NSLog("\(request.logPrefix) camera configuration failed: \(error.localizedDescription)")
        }
    }

    static func cameraSortKey(_ device: AVCaptureDevice) -> String {
        let priority: String
        if device.deviceType == .external, !device.isContinuityCamera {
            priority = "0"
        } else if device.deviceType == .builtInWideAngleCamera {
            priority = "1"
        } else if device.deviceType == .deskViewCamera {
            priority = "2"
        } else if device.isContinuityCamera {
            priority = "3"
        } else {
            priority = "4"
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
