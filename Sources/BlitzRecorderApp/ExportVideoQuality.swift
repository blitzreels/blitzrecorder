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
    let sizeEstimateIsCeiling: Bool

    var detail: String {
        switch codec {
        case .proRes422:
            return String(format: "ProRes 422 · almost lossless · %.0f Mbps", Double(bitrate) / 1_000_000)
        case .h264, .hevc:
            let codecName = codec.displayName
            if let quality, quality >= 0.85 {
                return String(format: "%@ · visually lossless · up to %.0f Mbps", codecName, Double(bitrate) / 1_000_000)
            }
            if usesAverageBitRate {
                return String(format: "%@ · %.1f Mbps", codecName, Double(bitrate) / 1_000_000)
            }
            return String(format: "%@ · up to %.1f Mbps", codecName, Double(bitrate) / 1_000_000)
        }
    }

    var typicalSizeFraction: Double {
        guard sizeEstimateIsCeiling, let quality else { return 1 }
        if quality >= 0.85 { return 0.22 }
        if quality >= 0.65 { return 0.38 }
        return 0.5
    }

    var estimatedSizeCaption: String {
        sizeEstimateIsCeiling ? "Typical–max" : "Estimated size"
    }

    func estimatedSizeText(duration: TimeInterval, layoutCount: Int = 1) -> String {
        let seconds = max(0, duration) * Double(max(1, layoutCount))
        let maximumBytes = Int64(seconds * Double(bitrate + audioBitrate) / 8)
        let typicalBytes = Int64((Double(maximumBytes) * typicalSizeFraction).rounded())
        if typicalBytes == maximumBytes {
            return "≈ " + Self.byteCount(maximumBytes)
        }
        return "≈ \(Self.byteCount(typicalBytes))–\(Self.byteCount(maximumBytes))"
    }

    private static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
            preferredFormat: nil,
            sizeEstimateIsCeiling: false
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
            return "Compact"
        case .web:
            return "Web"
        case .standard:
            return "Standard"
        case .high:
            return "High"
        case .maximum:
            return "Lossless"
        case .proRes:
            return "ProRes"
        }
    }

    var plainDescription: String {
        switch self {
        case .compact:
            return "Tiniest file · more loss"
        case .web:
            return "Clear H.264 · sharing and uploads"
        case .standard:
            return "Some loss · smaller HEVC"
        case .high:
            return "Light loss · most videos"
        case .maximum:
            return "Visually lossless HEVC"
        case .proRes:
            return "Almost lossless master · huge MOV"
        }
    }

    static var menuCases: [ExportVideoQuality] {
        [.compact, .web, .high, .maximum, .proRes]
    }

    var resolvedMenuQuality: ExportVideoQuality {
        self == .standard ? .high : self
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
                bitrate: scaledBitrate(baseBitrate, multiplier: 0.12),
                quality: 0.28,
                usesAverageBitRate: true,
                maxKeyFrameInterval: fps * 5,
                audioBitrate: min(audioBitrate, 96_000),
                prefersFullRangeRGB: false,
                preferredFormat: nil,
                sizeEstimateIsCeiling: false
            )
        case .web:
            return ExportEncodingProfile(
                codec: .h264,
                bitrate: scaledBitrate(baseBitrate, multiplier: 1.0),
                quality: 0.75,
                usesAverageBitRate: true,
                maxKeyFrameInterval: fps * 2,
                audioBitrate: min(audioBitrate, 192_000),
                prefersFullRangeRGB: false,
                preferredFormat: nil,
                sizeEstimateIsCeiling: false
            )
        case .standard:
            return ExportEncodingProfile(
                codec: .hevc,
                bitrate: scaledBitrate(baseBitrate, multiplier: 0.80),
                quality: 0.55,
                usesAverageBitRate: false,
                maxKeyFrameInterval: fps * 3,
                audioBitrate: audioBitrate,
                prefersFullRangeRGB: false,
                preferredFormat: nil,
                sizeEstimateIsCeiling: true
            )
        case .high:
            return ExportEncodingProfile(
                codec: .hevc,
                bitrate: scaledBitrate(baseBitrate, multiplier: 1.5),
                quality: 0.72,
                usesAverageBitRate: false,
                maxKeyFrameInterval: fps * 2,
                audioBitrate: audioBitrate,
                prefersFullRangeRGB: true,
                preferredFormat: nil,
                sizeEstimateIsCeiling: true
            )
        case .maximum:
            return ExportEncodingProfile(
                codec: .hevc,
                bitrate: scaledBitrate(baseBitrate, multiplier: 4),
                quality: 0.92,
                usesAverageBitRate: false,
                maxKeyFrameInterval: fps * 2,
                audioBitrate: max(audioBitrate, 256_000),
                prefersFullRangeRGB: true,
                preferredFormat: nil,
                sizeEstimateIsCeiling: true
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
                preferredFormat: .mov,
                sizeEstimateIsCeiling: false
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
