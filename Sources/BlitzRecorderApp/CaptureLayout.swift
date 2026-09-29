import CoreGraphics

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case paused
    case finishing

    var allowsWindowClose: Bool {
        self == .idle
    }
}

enum CaptureLayout: String, CaseIterable {
    case vertical = "Shorts 9:16"
    case horizontal = "YouTube 16:9"
    case square = "Square 1:1"

    var aspectRatio: CGFloat {
        switch self {
        case .vertical:
            return 9.0 / 16.0
        case .horizontal:
            return 16.0 / 9.0
        case .square:
            return 1
        }
    }
}

enum CaptureSource: String, CaseIterable {
    case screen = "Screen"
    case camera = "Camera"
    case systemAudio = "System Audio"
    case microphone = "Microphone"
}

enum SceneLayerKind: String, CaseIterable {
    case screen = "Screen"
    case camera = "Camera"
}

struct VideoSafeZoneMargins: Equatable {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    init(topPixels: CGFloat, bottomPixels: CGFloat, leftPixels: CGFloat, rightPixels: CGFloat) {
        top = topPixels / 1920
        bottom = bottomPixels / 1920
        left = leftPixels / 1080
        right = rightPixels / 1080
    }
}

enum SocialVideoSafeZone: String, CaseIterable {
    case none = "none"
    case tiktok = "tiktok"
    case instagramReels = "instagramReels"
    case facebookReels = "facebookReels"
    case youtubeShorts = "youtubeShorts"
    case crossPost = "crossPost"

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .tiktok:
            return "TikTok"
        case .instagramReels:
            return "Instagram Reels"
        case .facebookReels:
            return "Facebook Reels"
        case .youtubeShorts:
            return "YouTube Shorts"
        case .crossPost:
            return "Cross-post"
        }
    }


    var subtitle: String {
        switch self {
        case .none:
            return "No safe-area overlay"
        case .tiktok:
            return "Side actions, bottom CTA"
        case .instagramReels:
            return "Right rail, caption space"
        case .facebookReels:
            return "Reels action column"
        case .youtubeShorts:
            return "Bottom CTA, right rail"
        case .crossPost:
            return "Strictest of all platforms"
        }
    }

    var margins: VideoSafeZoneMargins? {
        switch self {
        case .none:
            return nil
        case .tiktok:
            return VideoSafeZoneMargins(topPixels: 200, bottomPixels: 370, leftPixels: 60, rightPixels: 180)
        case .instagramReels:
            return VideoSafeZoneMargins(topPixels: 220, bottomPixels: 340, leftPixels: 60, rightPixels: 120)
        case .facebookReels:
            return VideoSafeZoneMargins(topPixels: 180, bottomPixels: 340, leftPixels: 60, rightPixels: 160)
        case .youtubeShorts:
            return VideoSafeZoneMargins(topPixels: 180, bottomPixels: 390, leftPixels: 60, rightPixels: 120)
        case .crossPost:
            return VideoSafeZoneMargins(topPixels: 220, bottomPixels: 390, leftPixels: 60, rightPixels: 180)
        }
    }
}
