import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Darwin
import UIKit

struct RemoteCameraCaptureCapabilityBuilder {
    struct CinematicSupport {
        var supportsCinematicVideo: Bool
        var minimumAperture: Double?
        var maximumAperture: Double?
        var defaultAperture: Double?

        static let unavailable = CinematicSupport(
            supportsCinematicVideo: false,
            minimumAperture: nil,
            maximumAperture: nil,
            defaultAperture: nil
        )
    }

    let movieOutput: AVCaptureMovieFileOutput

    func device(for lens: RemoteCameraLens) -> AVCaptureDevice? {
        switch lens {
        case .ultraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .wide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .telephoto:
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        case .frontWide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    func cinematicDevice(for lens: RemoteCameraLens) -> AVCaptureDevice? {
        switch lens {
        case .wide:
            return AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? device(for: .wide)
        case .frontWide:
            return AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? device(for: .frontWide)
        case .ultraWide, .telephoto:
            return nil
        }
    }

    func supportedLenses() -> [RemoteCameraLens] {
        RemoteCameraLens.allCases.filter { device(for: $0) != nil }
    }

    func makeCapabilities(activeDevice: AVCaptureDevice) -> RemoteCameraCapabilities {
        let lenses = supportedLenses()
        let cinematic = cinematicCapabilities(activeVideoInputDevice: activeDevice)
        return RemoteCameraCapabilities(
            deviceName: UIDevice.current.name,
            deviceModelIdentifier: Self.deviceModelIdentifier(),
            supportedLenses: lenses,
            lensCapabilities: lenses.compactMap(makeLensCapabilities),
            supportedFormats: remoteFormats(for: activeDevice),
            supportedCaptureProfiles: RemoteCameraCaptureProfileResolver.supportedProfiles(
                for: activeDevice,
                movieOutput: movieOutput
            ),
            supportsTorch: false,
            minimumZoomFactor: 1,
            maximumZoomFactor: 1,
            supportsManualFocus: activeDevice.isLockingFocusWithCustomLensPositionSupported,
            supportsFocusLock: activeDevice.isFocusModeSupported(.locked),
            supportsManualExposure: activeDevice.isExposureModeSupported(.custom),
            supportsExposureLock: activeDevice.isExposureModeSupported(.locked),
            supportsWhiteBalanceLock: activeDevice.isWhiteBalanceModeSupported(.locked),
            supportsManualWhiteBalance: activeDevice.isWhiteBalanceModeSupported(.locked),
            supportedStabilizationModes: supportedStabilizationModes(for: activeDevice.activeFormat),
            supportedRotationDegrees: supportedRotationDegrees(),
            minimumExposureBias: Double(activeDevice.minExposureTargetBias),
            maximumExposureBias: Double(activeDevice.maxExposureTargetBias),
            minimumISO: Double(activeDevice.activeFormat.minISO),
            maximumISO: Double(activeDevice.activeFormat.maxISO),
            minimumShutterDurationSeconds: CMTimeGetSeconds(activeDevice.activeFormat.minExposureDuration),
            maximumShutterDurationSeconds: CMTimeGetSeconds(activeDevice.activeFormat.maxExposureDuration),
            supportsCinematicVideo: cinematic.supportsCinematicVideo,
            minimumCinematicAperture: cinematic.minimumAperture,
            maximumCinematicAperture: cinematic.maximumAperture,
            defaultCinematicAperture: cinematic.defaultAperture
        )
    }

    func cinematicCapabilities(activeVideoInputDevice: AVCaptureDevice?) -> CinematicSupport {
        if let activeVideoInputDevice {
            let activeCapabilities = cinematicCapabilities(for: activeVideoInputDevice)
            if activeCapabilities.supportsCinematicVideo {
                return activeCapabilities
            }
        }
        guard let cinematicLens = preferredCinematicLens(),
              let cinematicDevice = cinematicDevice(for: cinematicLens) ?? device(for: cinematicLens) else {
            return .unavailable
        }
        return cinematicCapabilities(for: cinematicDevice)
    }

    func cinematicCapabilities(for device: AVCaptureDevice) -> CinematicSupport {
        if #available(iOS 26.0, *) {
            let format = device.activeFormat.isCinematicVideoCaptureSupported
                ? device.activeFormat
                : device.formats.first { $0.isCinematicVideoCaptureSupported }
            guard let format else {
                return .unavailable
            }
            let minimumAperture = Double(format.minSimulatedAperture)
            return CinematicSupport(
                supportsCinematicVideo: true,
                minimumAperture: minimumAperture > 0 ? minimumAperture : nil,
                maximumAperture: minimumAperture > 0 ? Double(format.maxSimulatedAperture) : nil,
                defaultAperture: minimumAperture > 0 ? Double(format.defaultSimulatedAperture) : nil
            )
        }
        return .unavailable
    }

    func preferredCinematicLens() -> RemoteCameraLens? {
        let lenses = supportedLenses()
        let preferredOrder: [RemoteCameraLens] = [.wide, .telephoto, .ultraWide, .frontWide]
        return preferredOrder.first { lens in
            guard lenses.contains(lens),
                  let device = cinematicDevice(for: lens) ?? device(for: lens) else {
                return false
            }
            return cinematicCapabilities(for: device).supportsCinematicVideo
        }
    }

    func remoteFormats(
        for device: AVCaptureDevice,
        cinematicDevice: AVCaptureDevice? = nil
    ) -> [RemoteCameraFormat] {
        let cinematicFormatIDs = Set((cinematicDevice?.formats ?? [])
            .filter(Self.formatSupportsCinematicVideoCapture)
            .map(Self.formatID(for:)))
        return Array(
            Dictionary(grouping: device.formats, by: Self.formatID(for:))
            .compactMap { key, formats -> RemoteCameraFormat? in
                guard let first = formats.first else { return nil }
                let dimensions = CMVideoFormatDescriptionGetDimensions(first.formatDescription)
                let frameRates = supportedRemoteFrameRates(for: formats)
                guard !frameRates.isEmpty else { return nil }
                let colorModeFrameRates = supportedColorModeFrameRates(for: formats)
                return RemoteCameraFormat(
                    id: key,
                    width: Int(dimensions.width),
                    height: Int(dimensions.height),
                    frameRates: frameRates,
                    colorModes: Self.supportedColorModes(from: colorModeFrameRates),
                    colorModeFrameRates: colorModeFrameRates,
                    supportsStabilization: formats.contains(where: Self.formatSupportsStabilization),
                    supportsHDR: formats.contains { $0.isVideoHDRSupported },
                    supportsCinematicVideo: formats.contains(where: Self.formatSupportsCinematicVideoCapture)
                        || cinematicFormatIDs.contains(key)
                )
            }
            .sorted { lhs, rhs in
                let lhsArea = lhs.width * lhs.height
                let rhsArea = rhs.width * rhs.height
                if lhsArea == rhsArea {
                    return lhs.id < rhs.id
                }
                return lhsArea > rhsArea
            }
            .prefix(8)
        )
    }

    func supportedRemoteFrameRates(for formats: [AVCaptureDevice.Format]) -> [Int] {
        Array(Set(formats.flatMap { format in
            format.videoSupportedFrameRateRanges.flatMap { range in
                Self.preferredFrameRates.filter { range.minFrameRate <= Double($0) && range.maxFrameRate >= Double($0) }
            }
        })).sorted()
    }

    func supportedColorModeFrameRates(for formats: [AVCaptureDevice.Format]) -> [RemoteCameraColorMode: [Int]] {
        var result: [RemoteCameraColorMode: Set<Int>] = [.standard: Set(supportedRemoteFrameRates(for: formats))]
        for format in formats {
            let frameRates = Set(supportedRemoteFrameRates(for: [format]))
            guard !frameRates.isEmpty else { continue }
            for colorMode in Self.colorModes(for: format) {
                result[colorMode, default: []].formUnion(frameRates)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    func supportedStabilizationModes() -> [RemoteCameraStabilizationMode] {
        guard let device = device(for: .wide) else { return [.off] }
        return supportedStabilizationModes(for: device.activeFormat)
    }

    func supportedStabilizationModes(for format: AVCaptureDevice.Format) -> [RemoteCameraStabilizationMode] {
        var modes: [RemoteCameraStabilizationMode] = [.off]
        for (remoteMode, avMode) in Self.stabilizationModeMap where format.isVideoStabilizationModeSupported(avMode) {
            modes.append(remoteMode)
        }
        if #available(iOS 13.0, *),
           !modes.contains(.cinematic),
           format.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
            modes.append(.cinematic)
        }
        return modes
    }

    func supportedRotationDegrees() -> [Int] {
        [0, 90, 180, 270]
    }

    private func makeLensCapabilities(lens: RemoteCameraLens) -> RemoteCameraLensCapabilities? {
        guard let device = device(for: lens) else { return nil }
        let cinematicDevice = cinematicDevice(for: lens)
        let cinematic = cinematicCapabilities(for: cinematicDevice ?? device)
        return RemoteCameraLensCapabilities(
            lens: lens,
            supportedFormats: remoteFormats(for: device, cinematicDevice: cinematicDevice),
            supportedCaptureProfiles: RemoteCameraCaptureProfileResolver.supportedProfiles(
                for: device,
                movieOutput: movieOutput
            ),
            supportsTorch: device.hasTorch && device.isTorchAvailable,
            minimumZoomFactor: Double(device.minAvailableVideoZoomFactor),
            maximumZoomFactor: Double(device.maxAvailableVideoZoomFactor),
            supportsManualFocus: device.isLockingFocusWithCustomLensPositionSupported,
            supportsFocusLock: device.isFocusModeSupported(.locked),
            supportsManualExposure: device.isExposureModeSupported(.custom),
            supportsExposureLock: device.isExposureModeSupported(.locked),
            supportsWhiteBalanceLock: device.isWhiteBalanceModeSupported(.locked),
            supportsManualWhiteBalance: device.isWhiteBalanceModeSupported(.locked),
            supportedStabilizationModes: supportedStabilizationModes(for: device.activeFormat),
            minimumExposureBias: Double(device.minExposureTargetBias),
            maximumExposureBias: Double(device.maxExposureTargetBias),
            minimumISO: Double(device.activeFormat.minISO),
            maximumISO: Double(device.activeFormat.maxISO),
            minimumShutterDurationSeconds: CMTimeGetSeconds(device.activeFormat.minExposureDuration),
            maximumShutterDurationSeconds: CMTimeGetSeconds(device.activeFormat.maxExposureDuration),
            supportsCinematicVideo: cinematic.supportsCinematicVideo,
            minimumCinematicAperture: cinematic.minimumAperture,
            maximumCinematicAperture: cinematic.maximumAperture,
            defaultCinematicAperture: cinematic.defaultAperture
        )
    }

    private static func deviceModelIdentifier() -> String? {
        var size: size_t = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: machine)
    }

    private static func formatSupportsStabilization(_ format: AVCaptureDevice.Format) -> Bool {
        if [
            AVCaptureVideoStabilizationMode.standard,
            .cinematic,
            .auto
        ].contains(where: { format.isVideoStabilizationModeSupported($0) }) {
            return true
        }
        if #available(iOS 13.0, *) {
            return format.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced)
        }
        return false
    }

    private static func formatID(for format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height)"
    }

    private static func formatSupportsCinematicVideoCapture(_ format: AVCaptureDevice.Format) -> Bool {
        if #available(iOS 26.0, *) {
            return format.isCinematicVideoCaptureSupported
        }
        return false
    }

    private static func supportedColorModes(from frameRates: [RemoteCameraColorMode: [Int]]) -> [RemoteCameraColorMode] {
        let modes = RemoteCameraColorMode.allCases.filter { mode in
            frameRates[mode]?.isEmpty == false
        }
        return modes.isEmpty ? [.standard] : modes
    }

    private static func colorModes(for format: AVCaptureDevice.Format) -> [RemoteCameraColorMode] {
        var modes: [RemoteCameraColorMode] = [.standard]
        if format.supportedColorSpaces.contains(.appleLog) {
            modes.append(.appleLog)
        }
        if #available(iOS 26.0, *), format.supportedColorSpaces.contains(.appleLog2) {
            modes.append(.appleLog2)
        }
        return modes
    }

    private static let preferredFrameRates = [24, 25, 30, 60, 100, 120, 240]

    private static let stabilizationModeMap: [(RemoteCameraStabilizationMode, AVCaptureVideoStabilizationMode)] = [
        (.standard, .standard),
        (.cinematic, .cinematic),
        (.auto, .auto)
    ]
}
