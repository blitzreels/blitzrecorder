import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

enum ExportVideoCodec: String, CaseIterable {
    case h264
    case hevc
    case proRes422

    var displayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        case .proRes422:
            return "ProRes 422"
        }
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        case .proRes422:
            return .proRes422
        }
    }

    var cmCodecType: CMVideoCodecType {
        switch self {
        case .h264:
            return kCMVideoCodecType_H264
        case .hevc:
            return kCMVideoCodecType_HEVC
        case .proRes422:
            return kCMVideoCodecType_AppleProRes422
        }
    }

    var isMezzanine: Bool {
        self == .proRes422
    }

    var profileLevel: String? {
        switch self {
        case .h264:
            return AVVideoProfileLevelH264HighAutoLevel
        case .hevc:
            return kVTProfileLevel_HEVC_Main_AutoLevel as String
        case .proRes422:
            return nil
        }
    }
}

struct ExportEncodingProfile: Equatable {
    let codec: ExportVideoCodec
    let bitrate: Int
    let quality: Float?
    let usesAverageBitRate: Bool
    let maxKeyFrameInterval: Int?
    let audioBitrate: Int
    let prefersFullRangeRGB: Bool
    let preferredFormat: OutputVideoFormat?
    var prioritizesSpeed = false

    func prioritizingSpeed() -> ExportEncodingProfile {
        ExportEncodingProfile(
            codec: codec, bitrate: bitrate, quality: nil, usesAverageBitRate: true,
            maxKeyFrameInterval: maxKeyFrameInterval, audioBitrate: audioBitrate,
            prefersFullRangeRGB: false, preferredFormat: preferredFormat ?? .mp4, prioritizesSpeed: true)
    }

    /// Hits a chosen file size. ProRes has no bitrate control, so it keeps its own.
    func withVideoBitrate(_ videoBitrate: Int) -> ExportEncodingProfile {
        guard codec != .proRes422 else { return self }
        return ExportEncodingProfile(
            codec: codec, bitrate: min(RecordingSettings.maxCustomVideoBitrate, max(Self.minimumTargetBitrate, videoBitrate)),
            quality: quality, usesAverageBitRate: true, maxKeyFrameInterval: maxKeyFrameInterval,
            audioBitrate: audioBitrate, prefersFullRangeRGB: prefersFullRangeRGB, preferredFormat: preferredFormat,
            prioritizesSpeed: prioritizesSpeed)
    }

    static let minimumTargetBitrate = 300_000

    var detail: String {
        let megabits = Double(bitrate) / 1_000_000
        return codec == .proRes422
            ? String(format: "ProRes 422 · %.0f Mbps", megabits)
            : String(format: "%@ · %.1f Mbps", codec.displayName, megabits)
    }

    /// Every tier holds a fixed average bitrate, so the size follows from duration alone.
    func estimatedBytes(duration: TimeInterval, layoutCount: Int) -> Int64 {
        let seconds = max(0, duration) * Double(max(1, layoutCount))
        return Int64(seconds * Double(bitrate + audioBitrate) / 8)
    }

    func estimatedSizeText(duration: TimeInterval, layoutCount: Int) -> String {
        "≈ " + ByteCountFormatter.string(
            fromByteCount: estimatedBytes(duration: duration, layoutCount: layoutCount), countStyle: .file)
    }

    static func hevc(bitrate: Int, audioBitrate: Int) -> ExportEncodingProfile {
        ExportEncodingProfile(
            codec: .hevc,
            bitrate: bitrate,
            quality: nil,
            usesAverageBitRate: true,
            maxKeyFrameInterval: nil,
            audioBitrate: audioBitrate,
            prefersFullRangeRGB: false,
            preferredFormat: nil
        )
    }
}

enum ExportVideoQuality: String, CaseIterable {
    case compact
    case web
    case standard
    case high
    case maximum
    case proRes

    var displayName: String {
        switch self {
        case .compact:
            return "Small"
        case .web:
            return "Web"
        case .standard, .high, .maximum:
            return "High"
        case .proRes:
            return "Master"
        }
    }

    var plainDescription: String {
        switch self {
        case .compact:
            return "For messages and email"
        case .web:
            return "Plays anywhere and uploads fast"
        case .standard, .high, .maximum:
            return "Sharpest file for YouTube or editing later"
        case .proRes:
            return "For editing apps like Final Cut · very large"
        }
    }

    static var menuCases: [ExportVideoQuality] {
        [.compact, .web, .high, .proRes]
    }

    var resolvedMenuQuality: ExportVideoQuality {
        switch self {
        case .standard, .maximum: .high
        default: self
        }
    }

    var requiresQuickTime: Bool {
        self == .proRes
    }

    func resolvedOutputFormat(_ requested: OutputVideoFormat) -> OutputVideoFormat {
        requiresQuickTime ? .mov : requested
    }

    func videoBitrate(baseBitrate: Int) -> Int {
        encodingProfile(baseBitrate: baseBitrate, framesPerSecond: 30, audioBitrate: 192_000).bitrate
    }

    /// `baseBitrate` is the 1080p social reference (8 Mbps up to 30 fps), so Small ≈ 2.5, Web ≈ 5 and High ≈ 10 Mbps.
    func encodingProfile(
        baseBitrate: Int,
        framesPerSecond: Int,
        audioBitrate: Int,
        width: Int = 1_920,
        height: Int = 1_080
    ) -> ExportEncodingProfile {
        let fps = max(1, framesPerSecond)
        switch self {
        case .compact:
            return ExportEncodingProfile(
                codec: .hevc,
                bitrate: scaledBitrate(baseBitrate, multiplier: 0.3125),
                quality: nil,
                usesAverageBitRate: true,
                maxKeyFrameInterval: fps * 5,
                audioBitrate: min(audioBitrate, 96_000),
                prefersFullRangeRGB: false,
                preferredFormat: nil
            )
        case .web:
            return ExportEncodingProfile(
                codec: .h264,
                bitrate: scaledBitrate(baseBitrate, multiplier: 0.625),
                quality: nil,
                usesAverageBitRate: true,
                maxKeyFrameInterval: fps * 2,
                audioBitrate: min(audioBitrate, 160_000),
                prefersFullRangeRGB: false,
                preferredFormat: nil
            )
        case .standard, .high, .maximum:
            return ExportEncodingProfile(
                codec: .hevc,
                bitrate: scaledBitrate(baseBitrate, multiplier: 1.25),
                quality: nil,
                usesAverageBitRate: true,
                maxKeyFrameInterval: fps * 2,
                audioBitrate: audioBitrate,
                prefersFullRangeRGB: true,
                preferredFormat: nil
            )
        case .proRes:
            return ExportEncodingProfile(
                codec: .proRes422,
                bitrate: Self.proRes422Bitrate(width: width, height: height, framesPerSecond: fps),
                quality: nil,
                usesAverageBitRate: false,
                maxKeyFrameInterval: nil,
                audioBitrate: max(audioBitrate, 320_000),
                prefersFullRangeRGB: true,
                preferredFormat: .mov
            )
        }
    }

    private func scaledBitrate(_ baseBitrate: Int, multiplier: Double) -> Int {
        min(
            RecordingSettings.maxCustomVideoBitrate,
            max(RecordingSettings.minExportVideoBitrate, Int(Double(baseBitrate) * multiplier))
        )
    }

    private static func proRes422Bitrate(width: Int, height: Int, framesPerSecond: Int) -> Int {
        let apple1080p30 = 147_000_000.0
        let scale = Double(width * height) / (1_920.0 * 1_080.0) * Double(framesPerSecond) / 30.0
        return Int((apple1080p30 * scale).rounded())
    }
}

struct ExportPlaybackRate: Hashable, Codable, Sendable {
    static let all = (TimelineTimeMap.minimumPlaybackRateTenths...TimelineTimeMap.maximumPlaybackRateTenths).map {
        ExportPlaybackRate(tenths: $0)
    }
    static let normal = ExportPlaybackRate(tenths: TimelineTimeMap.minimumPlaybackRateTenths)

    let tenths: Int

    var value: Double { Double(tenths) / 10.0 }

    var displayName: String {
        String(format: "%.1f×", value)
    }

    init(tenths: Int) {
        self.tenths = TimelineTimeMap.clampedRateTenths(Double(tenths) / 10.0)
    }

    init(clamping value: Double) {
        tenths = TimelineTimeMap.clampedRateTenths(value)
    }
}

struct EditorExportRequest {
    let outputFormat: OutputVideoFormat
    let performanceProfile: ExportPerformanceProfile
    let hiddenVideoSources: Set<SceneLayerKind>
    let mutedAudioSources: Set<CaptureSource>
    let backgroundMusic: ExportBackgroundMusic?
    var playbackRate: Double = 1.0
}

struct ProjectExportRequest {
    var outputLayout: CaptureLayout? = nil
    let projectURL: URL
    let outputFormat: OutputVideoFormat
    let performanceProfile: ExportPerformanceProfile
    let destinationURL: URL
    let hiddenVideoSources: Set<SceneLayerKind>
    let mutedAudioSources: Set<CaptureSource>
    let backgroundMusic: ExportBackgroundMusic?
    var playbackRate: Double = 1.0
}

struct ExportBackgroundMusic {
    let url: URL
    var volume: Double
}
