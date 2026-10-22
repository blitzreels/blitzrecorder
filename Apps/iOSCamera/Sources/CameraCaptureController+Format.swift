import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation

@MainActor
extension CameraCaptureController {
    nonisolated static func activeFrameRate(for device: AVCaptureDevice) -> Int {
        let seconds = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(1, Int((1 / seconds).rounded()))
    }

    nonisolated static func activeColorMode(for device: AVCaptureDevice) -> RemoteCameraColorMode {
        if device.activeColorSpace == .appleLog {
            return .appleLog
        }
        if isAppleLog2(device.activeColorSpace) {
            return .appleLog2
        }
        return .standard
    }

    func applyFormat(_ settings: RemoteCameraSettings) async {
        guard let activeDevice,
              let formatID = settings.formatID,
              let format = captureFormat(for: settings, device: activeDevice) else {
            return
        }

        let colorSpace = Self.captureColorSpace(for: settings.colorMode, format: format)
        if activeFormatMatches(format, on: activeDevice, frameRate: settings.frameRate),
           activeColorSpaceMatches(colorSpace, on: activeDevice) {
            activeCaptureFormatLabel = "\(formatID) @ \(settings.frameRate) fps"
            return
        }

        let session = session
        let applied = await runOnSessionQueue { () -> Bool in
            do {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                try activeDevice.lockForConfiguration()
                defer { activeDevice.unlockForConfiguration() }
                session.automaticallyConfiguresCaptureDeviceForWideColor = colorSpace == nil
                activeDevice.activeFormat = format
                if let colorSpace {
                    activeDevice.activeColorSpace = colorSpace
                } else if activeDevice.activeColorSpace == .appleLog
                    || Self.isAppleLog2(activeDevice.activeColorSpace) {
                    activeDevice.activeColorSpace = .sRGB
                }
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, settings.frameRate)))
                Self.lockFrameDurationIfAvailable(
                    frameDuration,
                    videoInput: self.activeVideoInput,
                    device: activeDevice
                )
                Self.enableLensSmudgeDetectionIfAvailable(activeDevice)
                return true
            } catch {
                return false
            }
        }
        if applied {
            activeCaptureFormatLabel = "\(formatID) @ \(settings.frameRate) fps"
        } else {
            statusMessage = "Format not available"
        }
    }

    private func captureFormat(for settings: RemoteCameraSettings, device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        guard let formatID = settings.formatID else { return nil }
        return RemoteCameraCaptureProfileResolver.captureFormat(
            for: settings.captureProfileID,
            formatID: formatID,
            frameRate: settings.frameRate,
            device: device,
            colorMode: settings.colorMode,
            requiresCinematic: settings.cinematicVideoEnabled
        )
    }

    private func activeFormatMatches(
        _ format: AVCaptureDevice.Format,
        on device: AVCaptureDevice,
        frameRate: Int
    ) -> Bool {
        captureFormatsMatch(device.activeFormat, format) && Self.activeFrameRate(for: device) == frameRate
    }

    private func activeColorSpaceMatches(_ colorSpace: AVCaptureColorSpace?, on device: AVCaptureDevice) -> Bool {
        guard let colorSpace else {
            return device.activeColorSpace != .appleLog && !Self.isAppleLog2(device.activeColorSpace)
        }
        return device.activeColorSpace == colorSpace
    }

    private nonisolated static func lockFrameDurationIfAvailable(
        _ frameDuration: CMTime,
        videoInput: AVCaptureDeviceInput?,
        device: AVCaptureDevice
    ) {
        if #available(iOS 26.0, *),
           let videoInput,
           videoInput.isLockedVideoFrameDurationSupported,
           CMTIME_IS_VALID(device.minSupportedLockedVideoFrameDuration),
           CMTimeCompare(frameDuration, device.minSupportedLockedVideoFrameDuration) >= 0,
           Self.frameDuration(frameDuration, isSupportedBy: device.activeFormat) {
            videoInput.activeLockedVideoFrameDuration = frameDuration
        } else {
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }
    }

    private nonisolated static func frameDuration(
        _ frameDuration: CMTime,
        isSupportedBy format: AVCaptureDevice.Format
    ) -> Bool {
        guard CMTIME_IS_VALID(frameDuration),
              CMTimeCompare(frameDuration, .zero) > 0 else {
            return false
        }
        return format.videoSupportedFrameRateRanges.contains { range in
            CMTimeCompare(frameDuration, range.minFrameDuration) >= 0
                && CMTimeCompare(frameDuration, range.maxFrameDuration) <= 0
        }
    }

    private func captureFormatsMatch(_ lhs: AVCaptureDevice.Format, _ rhs: AVCaptureDevice.Format) -> Bool {
        guard CMFormatDescriptionEqual(lhs.formatDescription, otherFormatDescription: rhs.formatDescription) else {
            return false
        }
        if #available(iOS 26.0, *) {
            return lhs.isCinematicVideoCaptureSupported == rhs.isCinematicVideoCaptureSupported
                && abs(lhs.minSimulatedAperture - rhs.minSimulatedAperture) < 0.001
                && abs(lhs.maxSimulatedAperture - rhs.maxSimulatedAperture) < 0.001
                && abs(lhs.defaultSimulatedAperture - rhs.defaultSimulatedAperture) < 0.001
        }
        return true
    }

    func applyCaptureCodec(_ settings: RemoteCameraSettings) async -> RemoteCameraCaptureProfileID {
        let movieOutput = movieOutput
        let result = await runOnSessionQueue { () -> (RemoteCameraCaptureProfileID, String?) in
            guard let connection = movieOutput.connection(with: .video) else {
                return (.automatic, nil)
            }

            let resolved = RemoteCameraCaptureProfileResolver.resolveCodec(
                requestedProfileID: settings.captureProfileID,
                movieOutput: movieOutput
            )
            if let codec = resolved.codec {
                movieOutput.setOutputSettings([AVVideoCodecKey: codec.rawValue], for: connection)
            }
            return (resolved.profileID, resolved.codecLabel)
        }
        activeCaptureProfileID = result.0
        activeCaptureCodecLabel = result.1
        return result.0
    }

    private static func captureColorSpace(
        for colorMode: RemoteCameraColorMode,
        format: AVCaptureDevice.Format
    ) -> AVCaptureColorSpace? {
        switch colorMode {
        case .standard:
            return nil
        case .appleLog:
            return format.supportedColorSpaces.contains(.appleLog) ? .appleLog : nil
        case .appleLog2:
            if #available(iOS 26.0, *), format.supportedColorSpaces.contains(.appleLog2) {
                return .appleLog2
            }
            return nil
        }
    }

    private nonisolated static func isAppleLog2(_ colorSpace: AVCaptureColorSpace) -> Bool {
        if #available(iOS 26.0, *) {
            return colorSpace == .appleLog2
        }
        return false
    }
}
