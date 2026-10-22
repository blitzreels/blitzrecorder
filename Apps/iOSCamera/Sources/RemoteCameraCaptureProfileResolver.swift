import BlitzRecorderCore
@preconcurrency import AVFoundation
import Foundation

enum RemoteCameraCaptureProfileResolver {
    static func supportedProfiles(
        for device: AVCaptureDevice,
        movieOutput: AVCaptureMovieFileOutput
    ) -> [RemoteCameraCaptureProfile] {
        let formats = remoteFormats(for: device)
        let availableCodecs = movieOutput.availableVideoCodecTypes
        let proResFormatFrameRates = proResRemoteFormatFrameRates(for: device)
        let proResFormatIDs = Array(proResFormatFrameRates.keys).sorted()
        let hasProResFormat = !proResFormatIDs.isEmpty
        let hasProResStorage = hasMinimumProResStorageHeadroom()
        // The movie output only lists ProRes once a ProRes format is active, so a ProRes format is what counts.
        let proResReason: String? = if !hasProResFormat {
            "This iPhone camera does not expose a ProRes 422 capture format."
        } else if !hasProResStorage {
            "Free at least 10% iPhone storage for ProRes."
        } else {
            nil
        }

        return [
            RemoteCameraCaptureProfile(
                id: .automatic,
                displayName: "Auto",
                codecLabel: preferredAutomaticCodec(from: availableCodecs).map(Self.codecLabel)
            ),
            RemoteCameraCaptureProfile(
                id: .highEfficiency,
                displayName: "HEVC",
                isAvailable: availableCodecs.contains(.hevc),
                unavailableReason: availableCodecs.contains(.hevc) ? nil : "HEVC is not available.",
                codecLabel: "HEVC",
                supportedFormatIDs: formats.map(\.id),
                supportedFormatFrameRates: Dictionary(uniqueKeysWithValues: formats.map { ($0.id, $0.frameRates) })
            ),
            RemoteCameraCaptureProfile(
                id: .proRes422,
                displayName: "ProRes",
                isAvailable: proResReason == nil,
                unavailableReason: proResReason,
                codecLabel: "ProRes 422",
                supportedFormatIDs: proResFormatIDs,
                supportedFormatFrameRates: proResFormatFrameRates
            )
        ]
    }

    static func captureFormat(
        for profileID: RemoteCameraCaptureProfileID,
        formatID: String,
        frameRate: Int,
        device: AVCaptureDevice,
        colorMode: RemoteCameraColorMode = .standard,
        requiresCinematic: Bool = false
    ) -> AVCaptureDevice.Format? {
        let candidates = profileID == .proRes422 ? proResCaptureFormats(for: device) : device.formats
        return candidates.first { format in
            Self.formatID(for: format) == formatID
                && (!requiresCinematic || Self.formatSupportsCinematicVideoCapture(format))
                && Self.format(format, supports: colorMode)
                && format.supportsFrameRate(frameRate)
        }
    }

    static func preferredCinematicCaptureFormat(
        for device: AVCaptureDevice,
        preferredFrameRate: Int
    ) -> AVCaptureDevice.Format? {
        let candidates = rankedCinematicCaptureFormats(
            device.formats.filter(Self.formatSupportsCinematicVideoCapture),
            preferredFrameRate: preferredFrameRate
        )
        return candidates.first { $0.supportsFrameRate(preferredFrameRate) }
            ?? candidates.first { $0.supportsFrameRate(30) }
            ?? candidates.first
    }

    private static func rankedCinematicCaptureFormats(
        _ formats: [AVCaptureDevice.Format],
        preferredFrameRate: Int
    ) -> [AVCaptureDevice.Format] {
        formats.sorted { lhs, rhs in
            let lhsScore = cinematicCaptureFormatScore(lhs, preferredFrameRate: preferredFrameRate)
            let rhsScore = cinematicCaptureFormatScore(rhs, preferredFrameRate: preferredFrameRate)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return formatID(for: lhs) > formatID(for: rhs)
        }
    }

    private static func cinematicCaptureFormatScore(
        _ format: AVCaptureDevice.Format,
        preferredFrameRate: Int
    ) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let area = Int(dimensions.width) * Int(dimensions.height)
        let supportsPreferredRate = format.supportsFrameRate(preferredFrameRate)
        let supportsNativeCinematicRate = format.supportsFrameRate(30)
        return area
            + (supportsPreferredRate ? 1_000_000_000 : 0)
            + (supportsNativeCinematicRate ? 100_000_000 : 0)
    }

    static func resolveCodec(
        requestedProfileID: RemoteCameraCaptureProfileID,
        movieOutput: AVCaptureMovieFileOutput
    ) -> (profileID: RemoteCameraCaptureProfileID, codec: AVVideoCodecType?, codecLabel: String?) {
        let availableCodecs = movieOutput.availableVideoCodecTypes
        switch requestedProfileID {
        case .automatic:
            let codec = preferredAutomaticCodec(from: availableCodecs)
            return (.automatic, codec, codec.map(codecLabel))
        case .highEfficiency:
            guard availableCodecs.contains(.hevc) else {
                let codec = availableCodecs.first
                return (.automatic, codec, codec.map(codecLabel))
            }
            return (.highEfficiency, .hevc, "HEVC")
        case .proRes422:
            guard availableCodecs.contains(.proRes422) else {
                let codec = availableCodecs.first
                return (.automatic, codec, codec.map(codecLabel))
            }
            return (.proRes422, .proRes422, "ProRes 422")
        }
    }

    private static func remoteFormats(for device: AVCaptureDevice) -> [RemoteCameraFormat] {
        Array(
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
                        colorModes: supportedColorModes(from: colorModeFrameRates),
                        colorModeFrameRates: colorModeFrameRates,
                        supportsStabilization: formats.contains(where: Self.formatSupportsStabilization),
                        supportsHDR: formats.contains { $0.isVideoHDRSupported },
                        supportsCinematicVideo: formats.contains(where: Self.formatSupportsCinematicVideoCapture)
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

    private static func proResRemoteFormatFrameRates(for device: AVCaptureDevice) -> [String: [Int]] {
        Dictionary(grouping: proResCaptureFormats(for: device), by: Self.formatID(for:))
            .mapValues(supportedRemoteFrameRates)
            .filter { !$0.value.isEmpty }
    }

    private static func proResCaptureFormats(for device: AVCaptureDevice) -> [AVCaptureDevice.Format] {
        device.formats.filter(isProResSourceFormat)
    }

    private static func isProResSourceFormat(_ format: AVCaptureDevice.Format) -> Bool {
        format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
    }

    private static func supportedRemoteFrameRates(for formats: [AVCaptureDevice.Format]) -> [Int] {
        Array(Set(formats.flatMap { format in
            format.videoSupportedFrameRateRanges.flatMap { range in
                preferredFrameRates.filter { range.minFrameRate <= Double($0) && range.maxFrameRate >= Double($0) }
            }
        })).sorted()
    }

    private static func supportedColorModeFrameRates(for formats: [AVCaptureDevice.Format]) -> [RemoteCameraColorMode: [Int]] {
        var result: [RemoteCameraColorMode: Set<Int>] = [.standard: Set(supportedRemoteFrameRates(for: formats))]
        for format in formats {
            let frameRates = Set(supportedRemoteFrameRates(for: [format]))
            guard !frameRates.isEmpty else { continue }
            for colorMode in colorModes(for: format) {
                result[colorMode, default: []].formUnion(frameRates)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    private static func formatSupportsStabilization(_ format: AVCaptureDevice.Format) -> Bool {
        [
            AVCaptureVideoStabilizationMode.standard,
            .cinematic,
            .auto,
            .cinematicExtendedEnhanced
        ].contains(where: { format.isVideoStabilizationModeSupported($0) })
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

    private static func format(_ format: AVCaptureDevice.Format, supports colorMode: RemoteCameraColorMode) -> Bool {
        colorModes(for: format).contains(colorMode)
    }

    private static let preferredFrameRates = [24, 25, 30, 60, 100, 120, 240]

    private static func hasMinimumProResStorageHeadroom() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attributes[.systemFreeSize] as? NSNumber,
              let totalSize = attributes[.systemSize] as? NSNumber,
              totalSize.doubleValue > 0 else {
            return true
        }
        return freeSize.doubleValue / totalSize.doubleValue >= 0.10
    }

    static func codecLabel(_ codec: AVVideoCodecType) -> String {
        switch codec {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes422: return "ProRes 422"
        case .proRes4444: return "ProRes 4444"
        default: return codec.rawValue
        }
    }

    private static func preferredAutomaticCodec(from codecs: [AVVideoCodecType]) -> AVVideoCodecType? {
        if codecs.contains(.hevc) {
            return .hevc
        }
        return codecs.first
    }

    static func formatID(for format: AVCaptureDevice.Format) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return "\(dimensions.width)x\(dimensions.height)"
    }
}

private extension AVCaptureDevice.Format {
    func supportsFrameRate(_ frameRate: Int) -> Bool {
        videoSupportedFrameRateRanges.contains { range in
            range.minFrameRate <= Double(frameRate) && range.maxFrameRate >= Double(frameRate)
        }
    }
}
