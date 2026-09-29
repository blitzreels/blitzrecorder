import AVFoundation
import CoreGraphics

enum OutputResolution: String, CaseIterable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case p2160 = "4K"

    var displayName: String {
        rawValue
    }

    var height: Int {
        switch self {
        case .p720:
            return 720
        case .p1080:
            return 1080
        case .p1440:
            return 1440
        case .p2160:
            return 2160
        }
    }

    func dimensions(for layout: CaptureLayout) -> (width: Int, height: Int) {
        switch layout {
        case .vertical:
            return (height, height * 16 / 9)
        case .horizontal:
            return (height * 16 / 9, height)
        case .square:
            return (height, height)
        }
    }
}

enum OutputVideoFormat: String, CaseIterable {
    case mov = "mov"
    case mp4 = "mp4"
    case m4v = "m4v"

    var displayName: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        rawValue
    }

    var plainDescription: String {
        switch self {
        case .mov:
            return "Best for editing on a Mac"
        case .mp4:
            return "Best for sharing and uploading"
        case .m4v:
            return "For Apple devices and iTunes"
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .mov:
            return .mov
        case .mp4:
            return .mp4
        case .m4v:
            return .m4v
        }
    }
}

enum AudioQuality: String, CaseIterable {
    case standard
    case high
    case studio

    var bitrate: Int {
        switch self {
        case .standard:
            return 192_000
        case .high:
            return 256_000
        case .studio:
            return 320_000
        }
    }

    var displayName: String {
        switch self {
        case .standard:
            return "Normal"
        case .high:
            return "High"
        case .studio:
            return "Studio"
        }
    }

    var detail: String {
        "\(bitrate / 1000) kbps"
    }

    var plainDescription: String {
        switch self {
        case .standard:
            return "Great for most videos"
        case .high:
            return "Clearer voices and music"
        case .studio:
            return "Best for podcasts and music"
        }
    }
}

enum SourceAudioFormat: String, CaseIterable {
    case aac
    case wav

    var fileExtension: String {
        switch self {
        case .aac:
            return "m4a"
        case .wav:
            return "wav"
        }
    }

    var avFileType: AVFileType {
        switch self {
        case .aac:
            return .m4a
        case .wav:
            return .wav
        }
    }

    var isLossless: Bool {
        self == .wav
    }

    var displayName: String {
        switch self {
        case .aac:
            return "M4A"
        case .wav:
            return "WAV"
        }
    }

    var plainDescription: String {
        switch self {
        case .aac:
            return "Smaller files, good for sharing"
        case .wav:
            return "No quality lost, best for editing"
        }
    }
}

enum SocialVideoEncoding {
    static func videoBitrate(resolution: OutputResolution, fps: Int) -> Int {
        let highFrameRate = fps > 30
        switch resolution {
        case .p720:
            return highFrameRate ? 7_500_000 : 5_000_000
        case .p1080:
            return highFrameRate ? 12_000_000 : 8_000_000
        case .p1440:
            return highFrameRate ? 20_000_000 : 14_000_000
        case .p2160:
            return highFrameRate ? 35_000_000 : 24_000_000
        }
    }

    static func screenIntermediateBitrate(resolution: OutputResolution, layout: CaptureLayout, fps: Int) -> Int {
        let layoutMultiplier = layout == .vertical ? 0.9 : 1.0
        return Int(Double(videoBitrate(resolution: resolution, fps: fps)) * layoutMultiplier)
    }

    static func cameraIntermediateBitrate(resolution: OutputResolution, fps: Int) -> Int {
        switch resolution {
        case .p720:
            return fps > 30 ? 5_000_000 : 4_000_000
        case .p1080:
            return fps > 30 ? 8_000_000 : 6_000_000
        case .p1440:
            return fps > 30 ? 12_000_000 : 9_000_000
        case .p2160:
            return fps > 30 ? 18_000_000 : 14_000_000
        }
    }
}
