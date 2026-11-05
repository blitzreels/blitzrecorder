import AVFoundation
import CoreMedia
import Foundation

struct LocalCameraDeviceConfigurationRequest {
    let device: AVCaptureDevice
    let fps: Int
    let logPrefix: String
    let sizeLimit: LocalCameraFormatSizeLimit
}

struct LocalCameraAttachRequest {
    let session: AVCaptureSession
    let device: AVCaptureDevice
    let fps: Int
    let sizeLimit: LocalCameraFormatSizeLimit
}

struct LocalCameraBestFormatRequest {
    let device: AVCaptureDevice
    let fps: Int
    let sizeLimit: LocalCameraFormatSizeLimit
}

enum LocalCameraFormatSizeLimit {
    case recording
    case cutoutPreview

    var width: Int32 { self == .recording ? 3840 : 1920 }
    var height: Int32 { self == .recording ? 2160 : 1080 }
}

enum LocalCameraSessionConfiguration {
    @discardableResult
    static func attachCamera(_ request: LocalCameraAttachRequest) throws -> Bool {
        let input = try AVCaptureDeviceInput(device: request.device)
        guard request.session.canAddInput(input) else { return false }
        request.session.addInput(input)
        applyPreset(.init(device: request.device, fps: request.fps, sizeLimit: request.sizeLimit), to: request.session)
        return true
    }

    static func holdBestFormat(_ request: LocalCameraDeviceConfigurationRequest) -> Bool {
        do {
            try request.device.lockForConfiguration()
        } catch {
            NSLog("\(request.logPrefix) camera configuration failed: \(error.localizedDescription)")
            return false
        }
        applyBestFormat(request)
        return true
    }

    @discardableResult
    static func restoreBestFormat(_ request: LocalCameraDeviceConfigurationRequest) -> Bool {
        let wanted = bestFormat(.init(device: request.device, fps: request.fps, sizeLimit: request.sizeLimit))
        guard let wanted, wanted != request.device.activeFormat else { return false }
        guard holdBestFormat(request) else { return false }
        request.device.unlockForConfiguration()
        return true
    }

    static func bestFormat(_ request: LocalCameraBestFormatRequest) -> AVCaptureDevice.Format? {
        let withinLimit = request.device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width <= request.sizeLimit.width && dimensions.height <= request.sizeLimit.height
        }
        let pool = withinLimit.isEmpty ? request.device.formats : withinLimit
        let reachingRate = pool.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate + 0.5 >= Double(request.fps) }
        }
        let candidates = reachingRate.isEmpty ? pool : reachingRate
        return candidates.min { cameraFormatSortKey($0) < cameraFormatSortKey($1) }
    }

    private static func applyPreset(_ request: LocalCameraBestFormatRequest, to session: AVCaptureSession) {
        let preset = bestFormat(request).flatMap(sessionPreset(matching:)) ?? .high
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high
    }

    private static func sessionPreset(matching format: AVCaptureDevice.Format) -> AVCaptureSession.Preset? {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        switch (dimensions.width, dimensions.height) {
        case (3840, 2160): return .hd4K3840x2160
        case (1920, 1080): return .hd1920x1080
        case (1280, 720): return .hd1280x720
        case (960, 540): return .qHD960x540
        case (640, 480): return .vga640x480
        default: return nil
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

    /// Needs the device lock.
    private static func applyBestFormat(_ request: LocalCameraDeviceConfigurationRequest) {
        let bestRequest = LocalCameraBestFormatRequest(device: request.device, fps: request.fps, sizeLimit: request.sizeLimit)
        if let format = bestFormat(bestRequest) {
            request.device.activeFormat = format
        }
        guard shouldForceFrameDuration(for: request.device),
              let duration = frameDuration(.init(format: request.device.activeFormat, fps: request.fps)) else { return }
        request.device.activeVideoMinFrameDuration = duration
        request.device.activeVideoMaxFrameDuration = duration
    }

    private struct FrameDurationRequest {
        let format: AVCaptureDevice.Format
        let fps: Int
    }

    private static func frameDuration(_ request: FrameDurationRequest) -> CMTime? {
        let wanted = Double(request.fps)
        let ranges = request.format.videoSupportedFrameRateRanges
        if let match = ranges.first(where: { $0.minFrameRate - 0.5 <= wanted && $0.maxFrameRate + 0.5 >= wanted }) {
            return match.maxFrameRate - match.minFrameRate < 0.5
                ? match.minFrameDuration
                : CMTime(value: 1, timescale: CMTimeScale(request.fps))
        }
        let slower = ranges.filter { $0.maxFrameRate < wanted }.max { $0.maxFrameRate < $1.maxFrameRate }
        return (slower ?? ranges.min { $0.minFrameRate < $1.minFrameRate })?.minFrameDuration
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
