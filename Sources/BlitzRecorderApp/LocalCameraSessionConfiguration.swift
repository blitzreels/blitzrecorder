import AVFoundation
import CoreMedia
import Foundation

struct LocalCameraDeviceConfigurationRequest {
    let device: AVCaptureDevice
    let fps: Int
    let logPrefix: String
    let cameraIsRunningSomewhere: Bool
}

struct LocalCameraAttachRequest {
    let session: AVCaptureSession
    let device: AVCaptureDevice
}

enum LocalCameraSessionConfiguration {
    /// Adds the camera to the session under the 1080p preset. Its best format is applied by `holdBestFormat` right
    /// before the session starts. Returns false when the session refuses the input.
    @discardableResult
    static func attachCamera(_ request: LocalCameraAttachRequest) throws -> Bool {
        let input = try AVCaptureDeviceInput(device: request.device)
        guard request.session.canAddInput(input) else { return false }
        request.session.addInput(input)
        configurePreset(on: request.session)
        return true
    }

    /// Locks the camera on its best format and frame rate. On macOS a session re-applies its preset when it starts
    /// unless the device is locked, so a format set earlier is lost (an Osmo recorded 1080×608 at 25 fps). Call
    /// right before `startRunning()`, and unlock the device after it when this returns true.
    static func holdBestFormat(_ request: LocalCameraDeviceConfigurationRequest) -> Bool {
        guard !request.cameraIsRunningSomewhere else { return false }
        do {
            try request.device.lockForConfiguration()
        } catch {
            NSLog("\(request.logPrefix) camera configuration failed: \(error.localizedDescription)")
            return false
        }
        applyBestFormat(request)
        return true
    }

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

        return CaptureDeviceCatalog.connectedCameras().first
    }

    static func configure(_ request: LocalCameraDeviceConfigurationRequest) {
        guard holdBestFormat(request) else { return }
        request.device.unlockForConfiguration()
    }

    /// Needs the device lock.
    private static func applyBestFormat(_ request: LocalCameraDeviceConfigurationRequest) {
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
               $0.minFrameRate <= Double(request.fps) && $0.maxFrameRate >= Double(request.fps)
           }) {
            request.device.activeVideoMinFrameDuration = frameDuration
            request.device.activeVideoMaxFrameDuration = frameDuration
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

    /// USB cameras often default to 25 fps; ask for the take's rate when the format offers it. Continuity Camera
    /// manages its own frame rate.
    private static func shouldForceFrameDuration(for device: AVCaptureDevice) -> Bool {
        device.deviceType == .builtInWideAngleCamera || (device.deviceType == .external && !device.isContinuityCamera)
    }
}
