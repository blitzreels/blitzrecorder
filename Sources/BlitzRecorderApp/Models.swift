import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreGraphics
import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case paused
    case finishing
}

enum CaptureLayout: String, CaseIterable {
    case vertical = "Shorts 9:16"
    case horizontal = "YouTube 16:9"

    var aspectRatio: CGFloat {
        switch self {
        case .vertical:
            return 9.0 / 16.0
        case .horizontal:
            return 16.0 / 9.0
        }
    }
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

    var shortName: String {
        switch self {
        case .none:
            return "Off"
        case .tiktok:
            return "TikTok"
        case .instagramReels:
            return "Instagram"
        case .facebookReels:
            return "Facebook"
        case .youtubeShorts:
            return "Shorts"
        case .crossPost:
            return "Cross-post"
        }
    }

    var iconName: String {
        switch self {
        case .none:
            return "rectangle.slash"
        case .tiktok:
            return "music.note"
        case .instagramReels:
            return "camera.aperture"
        case .facebookReels:
            return "play.square.fill"
        case .youtubeShorts:
            return "play.rectangle.fill"
        case .crossPost:
            return "square.on.square"
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
        }
    }

    func bitrateScale(for layout: CaptureLayout) -> Double {
        let selected = dimensions(for: layout)
        let baseline = OutputResolution.p1080.dimensions(for: layout)
        let selectedPixels = Double(selected.width * selected.height)
        let baselinePixels = Double(baseline.width * baseline.height)
        return selectedPixels / baselinePixels
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

enum CameraInsetAlignment: String, CaseIterable {
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .bottomLeft:
            return "Left"
        case .bottomRight:
            return "Right"
        }
    }

    var symbolName: String {
        switch self {
        case .bottomLeft:
            return "arrow.down.left"
        case .bottomRight:
            return "arrow.down.right"
        }
    }
}

enum CameraInsetShape: String, CaseIterable {
    case landscape
    case portrait

    var displayName: String {
        switch self {
        case .landscape:
            return "Wide"
        case .portrait:
            return "Vertical"
        }
    }

    var symbolName: String {
        switch self {
        case .landscape:
            return "rectangle"
        case .portrait:
            return "rectangle.portrait"
        }
    }

    var aspectRatio: CGFloat {
        switch self {
        case .landscape:
            return 16.0 / 9.0
        case .portrait:
            return 9.0 / 16.0
        }
    }

    func aspectRatio(forSource sourceAspectRatio: CGFloat) -> CGFloat {
        guard sourceAspectRatio > 0 else { return aspectRatio }
        switch self {
        case .landscape:
            return max(sourceAspectRatio, 1 / sourceAspectRatio)
        case .portrait:
            return min(sourceAspectRatio, 1 / sourceAspectRatio)
        }
    }
}

enum CameraContentMode: String, CaseIterable, Codable {
    case fill
    case fit

    var displayName: String {
        switch self {
        case .fill:
            return "Fill"
        case .fit:
            return "Fit"
        }
    }

    var symbolName: String {
        switch self {
        case .fill:
            return "arrow.up.left.and.arrow.down.right"
        case .fit:
            return "rectangle"
        }
    }

    var renderContentMode: VideoRenderContentMode {
        switch self {
        case .fill:
            return .aspectFill
        case .fit:
            return .aspectFit
        }
    }
}

enum ScenePreset: String, CaseIterable {
    case stackedHalves = "Stacked"
    case screenTop50 = "Screen 50%"
    case screenTop70 = "Screen 70%"
    case screenFocus = "Screen Focus"
    case cameraInset = "Camera Inset"
    case cameraFocus = "Camera Focus"
    case webcamLeft = "Webcam Left"
    case screenFullscreen = "Screen Fullscreen"
    case webcamFullscreen = "Webcam Fullscreen"

    static var allCases: [ScenePreset] {
        [
            .screenTop50,
            .cameraInset,
            .webcamLeft,
            .screenFullscreen,
            .webcamFullscreen
        ]
    }

    var detail: String {
        switch self {
        case .stackedHalves:
            return "Screen top"
        case .screenTop50:
            return "Screen 50%"
        case .screenTop70:
            return "Legacy split"
        case .screenFocus:
            return "Screen crop"
        case .cameraInset:
            return "Cam corner"
        case .cameraFocus:
            return "Speaker main"
        case .webcamLeft:
            return "Webcam left"
        case .screenFullscreen:
            return "Screen 100%"
        case .webcamFullscreen:
            return "Webcam 100%"
        }
    }
}

enum CanvasBackgroundStyle: String, CaseIterable {
    case black = "black"
    case graphite = "graphite"
    case slate = "slate"
    case midnight = "midnight"
    case ocean = "ocean"
    case aurora = "aurora"
    case nebula = "nebula"
    case macOSSonoma = "macos-sonoma"
    case macOSSonomaHorizon = "macos-sonoma-horizon"
    case macOSRadialSky = "macos-radial-sky"
    case macOSIMacBlue = "macos-imac-blue"
    case macOSIMacPurple = "macos-imac-purple"
    case macOSVentura = "macos-ventura"
    case macOSMonterey = "macos-monterey"
    case macOSBigSur = "macos-big-sur"
    case seasonalSpringAurora = "seasonal-spring-aurora"
    case seasonalSummerCoast = "seasonal-summer-coast"
    case seasonalAutumnSonoma = "seasonal-autumn-sonoma"
    case seasonalWinterFrost = "seasonal-winter-frost"
    case seasonalMidnightLake = "seasonal-midnight-lake"
    case studioGraphiteGlass = "studio-graphite-glass"
    case studioPaperWhite = "studio-paper-white"
    case studioSoftSpotlight = "studio-soft-spotlight"
    case monterey = "monterey"
    case sunset = "sunset"
    case dune = "dune"
    case blush = "blush"
    case silver = "silver"

    var displayName: String {
        switch self {
        case .black:
            return "Black"
        case .graphite:
            return "Titanium"
        case .slate:
            return "Slate"
        case .midnight:
            return "Midnight"
        case .ocean:
            return "Lagoon"
        case .aurora:
            return "Aurora"
        case .nebula:
            return "Nebula"
        case .macOSSonoma:
            return "macOS Sonoma"
        case .macOSSonomaHorizon:
            return "Sonoma Horizon"
        case .macOSRadialSky:
            return "Radial Sky"
        case .macOSIMacBlue:
            return "iMac Blue"
        case .macOSIMacPurple:
            return "iMac Purple"
        case .macOSVentura:
            return "macOS Ventura"
        case .macOSMonterey:
            return "macOS Monterey"
        case .macOSBigSur:
            return "macOS Big Sur"
        case .seasonalSpringAurora:
            return "Spring Aurora"
        case .seasonalSummerCoast:
            return "Summer Coast"
        case .seasonalAutumnSonoma:
            return "Autumn Sonoma"
        case .seasonalWinterFrost:
            return "Winter Frost"
        case .seasonalMidnightLake:
            return "Midnight Lake"
        case .studioGraphiteGlass:
            return "Graphite Glass"
        case .studioPaperWhite:
            return "Paper White"
        case .studioSoftSpotlight:
            return "Soft Spotlight"
        case .monterey:
            return "Monterey"
        case .sunset:
            return "Ember"
        case .dune:
            return "Dune"
        case .blush:
            return "Blush"
        case .silver:
            return "Liquid Silver"
        }
    }
}

struct SourceOption: Equatable {
    let id: String
    let name: String
}

struct ScreenSourceBinding: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case display
        case application
        case window
    }

    var kind: Kind
    var displayID: String?
    var bundleIdentifier: String?
    var applicationName: String?
    var processID: Int32?
    var windowID: UInt32?
    var windowTitle: String?

    var id: String {
        switch kind {
        case .display:
            return "display:\(displayID ?? "auto")"
        case .application:
            return "application:\(bundleIdentifier ?? applicationName ?? "\(processID ?? 0)")"
        case .window:
            return "window:\(windowID.map(String.init) ?? "\(bundleIdentifier ?? ""):\(windowTitle ?? "")")"
        }
    }

    var displayName: String {
        switch kind {
        case .display:
            return "Display \(displayID ?? "Auto")"
        case .application:
            return applicationName ?? bundleIdentifier ?? "Application"
        case .window:
            if let applicationName, let windowTitle, !windowTitle.isEmpty {
                return "\(applicationName) - \(windowTitle)"
            }
            return windowTitle ?? applicationName ?? "Window"
        }
    }

    var isConcreteSelection: Bool {
        switch kind {
        case .display:
            return displayID != nil
        case .application, .window:
            return true
        }
    }

    static func display(id: String?, name: String? = nil) -> ScreenSourceBinding {
        ScreenSourceBinding(
            kind: .display,
            displayID: id,
            bundleIdentifier: nil,
            applicationName: name,
            processID: nil,
            windowID: nil,
            windowTitle: nil
        )
    }
}

struct ScreenSourceOption: Equatable, Identifiable {
    let binding: ScreenSourceBinding
    let title: String
    let subtitle: String
    let systemImage: String
    let icon: NSImage?

    var id: String { binding.id }

    static func == (lhs: ScreenSourceOption, rhs: ScreenSourceOption) -> Bool {
        lhs.binding == rhs.binding
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.systemImage == rhs.systemImage
    }
}

struct SceneLayout: Equatable {
    var screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var cameraFrame: CGRect = CGRect(x: 0, y: 0.046796875, width: 1, height: 0.31640625)
    var layerOrder: [SceneLayerKind] = [.screen, .camera]

    static func defaultLayout(
        for layout: CaptureLayout,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio,
        cameraAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> SceneLayout {
        presetLayout(
            .defaultPreset(for: layout),
            for: layout,
            screenAspectRatio: screenAspectRatio,
            cameraAspectRatio: cameraAspectRatio
        )
    }

    static func presetLayout(
        _ preset: ScenePreset,
        for layout: CaptureLayout,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio,
        cameraAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> SceneLayout {
        switch layout {
        case .vertical:
            verticalPresetLayout(preset, screenAspectRatio: screenAspectRatio, cameraAspectRatio: cameraAspectRatio)
        case .horizontal:
            horizontalPresetLayout(preset, screenAspectRatio: screenAspectRatio, cameraAspectRatio: cameraAspectRatio)
        }
    }

    private static func verticalPresetLayout(
        _ preset: ScenePreset,
        screenAspectRatio: CGFloat,
        cameraAspectRatio: CGFloat
    ) -> SceneLayout {
        let canvasAR = CaptureLayout.vertical.aspectRatio
        switch preset {
        case .stackedHalves:
            var sceneLayout = SceneLayout()
            let screenHeight = fullWidthSourceHeight(
                sourceAspectRatio: screenAspectRatio,
                canvasAspectRatio: canvasAR
            )
            sceneLayout.screenFrame = CGRect(x: 0, y: 1 - screenHeight, width: 1, height: screenHeight)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1 - screenHeight)
            return sceneLayout
        case .screenTop50:
            return screenSplitLayout(screenHeight: defaultScreenSplitHeight, screenAspectRatio: screenAspectRatio)
        case .screenTop70:
            return screenSplitLayout(screenHeight: 0.7, screenAspectRatio: screenAspectRatio)
        case .screenFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = CGRect(x: 0.455, y: 0.045, width: 0.5, height: 0.25)
            return sceneLayout
        case .cameraInset:
            return cameraInsetLayout(
                for: .vertical,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        case .cameraFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = fittedSourceFrame(
                sourceAspectRatio: screenAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.06, y: 0.67, width: 0.88, height: 0.28)
            )
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamLeft:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        case .screenFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        }
    }

    private static func horizontalPresetLayout(
        _ preset: ScenePreset,
        screenAspectRatio: CGFloat,
        cameraAspectRatio: CGFloat
    ) -> SceneLayout {
        let canvasAR = CaptureLayout.horizontal.aspectRatio
        switch preset {
        case .stackedHalves:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
            return sceneLayout
        case .screenTop50:
            return horizontalPresetLayout(
                .stackedHalves,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        case .screenTop70:
            return horizontalPresetLayout(
                .stackedHalves,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        case .screenFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.73, y: 0.05, width: 0.22, height: 0.22)
            )
            return sceneLayout
        case .cameraInset:
            return cameraInsetLayout(
                for: .horizontal,
                screenAspectRatio: screenAspectRatio,
                cameraAspectRatio: cameraAspectRatio
            )
        case .cameraFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = fittedSourceFrame(
                sourceAspectRatio: screenAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.66, y: 0.62, width: 0.3, height: 0.3)
            )
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamLeft:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        case .screenFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sceneLayout.cameraFrame = canvasFillingFrame(sourceAspectRatio: cameraAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.layerOrder = [.camera, .screen]
            return sceneLayout
        case .webcamFullscreen:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR
            )
            sceneLayout.layerOrder = [.screen, .camera]
            return sceneLayout
        }
    }

    static let cameraAspectRatio: CGFloat = 16.0 / 9.0
    static let defaultScreenAspectRatio: CGFloat = 16.0 / 9.0
    static let defaultScreenSplitHeight: CGFloat = 0.5
    static let minimumScreenSplitHeight: CGFloat = 0.3
    static let maximumScreenSplitHeight: CGFloat = 0.75
    static let defaultCameraInsetSize: CGFloat = 0.28
    static let minimumCameraInsetSize: CGFloat = 0.18
    static let maximumCameraInsetSize: CGFloat = 0.52
    static let cameraInsetMargin: CGFloat = 0.035
    static let maximumCameraFramePadding: CGFloat = 0.18

    static func defaultCameraInsetSize(for layout: CaptureLayout) -> CGFloat {
        switch layout {
        case .horizontal:
            return defaultCameraInsetSize
        case .vertical:
            return maximumCameraInsetSize(for: layout)
        }
    }

    static func maximumCameraInsetSize(for layout: CaptureLayout) -> CGFloat {
        switch layout {
        case .horizontal:
            return maximumCameraInsetSize
        case .vertical:
            return max(minimumCameraInsetSize, 1 - cameraInsetMargin * 2)
        }
    }

    static func screenSplitLayout(
        screenHeight: CGFloat,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio
    ) -> SceneLayout {
        let screenHeight = clampedScreenSplitHeight(screenHeight)

        var sceneLayout = SceneLayout()
        sceneLayout.screenFrame = CGRect(
            x: 0,
            y: 1 - screenHeight,
            width: 1,
            height: screenHeight
        )
        sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 1 - screenHeight)
        return sceneLayout
    }

    static func cameraInsetLayout(
        for layout: CaptureLayout,
        alignment: CameraInsetAlignment = .bottomRight,
        shape: CameraInsetShape = .landscape,
        size: CGFloat? = nil,
        screenAspectRatio: CGFloat = defaultScreenAspectRatio,
        cameraAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> SceneLayout {
        let size = size ?? defaultCameraInsetSize(for: layout)
        var sceneLayout = SceneLayout()
        sceneLayout.screenFrame = canvasFillingFrame(
            sourceAspectRatio: screenAspectRatio,
            canvasAspectRatio: layout.aspectRatio
        )
        sceneLayout.cameraFrame = cameraInsetFrame(
            for: layout,
            alignment: alignment,
            shape: shape,
            size: size,
            sourceAspectRatio: cameraAspectRatio
        )
        sceneLayout.layerOrder = [.screen, .camera]
        return sceneLayout
    }

    static func cameraInsetFrame(
        for layout: CaptureLayout,
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat,
        sourceAspectRatio: CGFloat = SceneLayout.cameraAspectRatio
    ) -> CGRect {
        let availableWidth = max(0.001, 1 - cameraInsetMargin * 2)
        let availableHeight = max(0.001, 1 - cameraInsetMargin * 2)
        let dominantSize = min(maximumCameraInsetSize(for: layout), max(minimumCameraInsetSize, size))
        let canvasAspectRatio = layout.aspectRatio
        let shapeAspectRatio = shape.aspectRatio(forSource: sourceAspectRatio)

        var width: CGFloat
        var height: CGFloat
        switch shape {
        case .landscape:
            width = dominantSize
            height = width * canvasAspectRatio / shapeAspectRatio
        case .portrait:
            height = dominantSize
            width = height * shapeAspectRatio / canvasAspectRatio
        }

        let fitScale = min(1, availableWidth / width, availableHeight / height)
        width *= fitScale
        height *= fitScale

        let x: CGFloat
        switch alignment {
        case .bottomLeft:
            x = cameraInsetMargin
        case .bottomRight:
            x = 1 - cameraInsetMargin - width
        }

        return CGRect(x: x, y: cameraInsetMargin, width: width, height: height)
    }

    static func cameraInsetAlignment(for frame: CGRect) -> CameraInsetAlignment {
        frame.standardized.midX < 0.5 ? .bottomLeft : .bottomRight
    }

    static func isCameraInsetFrame(_ frame: CGRect) -> Bool {
        let frame = frame.standardized
        guard frame.width > 0.0001, frame.height > 0.0001 else { return false }
        guard abs(frame.minY - cameraInsetMargin) < 0.005 else { return false }
        let leftAnchored = abs(frame.minX - cameraInsetMargin) < 0.005
        let rightAnchored = abs(frame.maxX - (1 - cameraInsetMargin)) < 0.005
        return leftAnchored || rightAnchored
    }

    static func cameraInsetShape(for frame: CGRect, in layout: CaptureLayout) -> CameraInsetShape {
        cameraInsetAspectRatio(for: frame, in: layout) < 1 ? .portrait : .landscape
    }

    static func cameraInsetSize(for frame: CGRect, in layout: CaptureLayout) -> CGFloat {
        let frame = frame.standardized
        switch cameraInsetShape(for: frame, in: layout) {
        case .landscape:
            return min(maximumCameraInsetSize(for: layout), max(minimumCameraInsetSize, frame.width))
        case .portrait:
            return min(maximumCameraInsetSize(for: layout), max(minimumCameraInsetSize, frame.height))
        }
    }

    private static func cameraInsetAspectRatio(for frame: CGRect, in layout: CaptureLayout) -> CGFloat {
        let frame = frame.standardized
        guard frame.width > 0, frame.height > 0 else {
            return CameraInsetShape.landscape.aspectRatio
        }
        return (frame.width / frame.height) * layout.aspectRatio
    }

    static func clampedScreenSplitHeight(_ height: CGFloat) -> CGFloat {
        min(maximumScreenSplitHeight, max(minimumScreenSplitHeight, height))
    }

    static func canvasFillingFrame(sourceAspectRatio: CGFloat, canvasAspectRatio: CGFloat) -> CGRect {
        guard sourceAspectRatio > 0, canvasAspectRatio > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let sourceARInCanvasCoords = sourceAspectRatio / canvasAspectRatio
        if sourceARInCanvasCoords >= 1 {
            let w = sourceARInCanvasCoords
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else {
            let h = 1 / sourceARInCanvasCoords
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
    }

    static func fittedSourceFrame(
        sourceAspectRatio: CGFloat,
        canvasAspectRatio: CGFloat,
        in container: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> CGRect {
        guard sourceAspectRatio > 0,
              canvasAspectRatio > 0,
              !container.isEmpty else {
            return container
        }

        let containerAspectRatio = (container.width / container.height) * canvasAspectRatio
        let width: CGFloat
        let height: CGFloat
        if containerAspectRatio > sourceAspectRatio {
            height = container.height
            width = height * sourceAspectRatio / canvasAspectRatio
        } else {
            width = container.width
            height = width * canvasAspectRatio / sourceAspectRatio
        }

        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func fullWidthSourceHeight(sourceAspectRatio: CGFloat, canvasAspectRatio: CGFloat) -> CGFloat {
        guard sourceAspectRatio > 0, canvasAspectRatio > 0 else { return 0.5 }
        return min(0.65, max(0.2, canvasAspectRatio / sourceAspectRatio))
    }

    func frame(for kind: SceneLayerKind) -> CGRect {
        switch kind {
        case .screen:
            return screenFrame
        case .camera:
            return cameraFrame
        }
    }

    var screenSplitHeight: CGFloat? {
        let screen = screenFrame.standardized
        let camera = cameraFrame.standardized
        guard almostEqual(camera.minX, 0),
              almostEqual(camera.minY, 0),
              almostEqual(camera.width, 1),
              almostEqual(screen.maxY, 1),
              almostEqual(screen.minY, camera.maxY),
              screen.height >= SceneLayout.minimumScreenSplitHeight,
              screen.height <= SceneLayout.maximumScreenSplitHeight else {
            return nil
        }
        return screen.height
    }

    private func almostEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}

struct RecordingScene: Equatable {
    var enabledSources: Set<CaptureSource>
    var sceneLayout: SceneLayout
    var screenSourceGeometry: ScreenSourceGeometry
    var cameraCropAmount: CGPoint
    var cameraCropPosition: CGPoint
    var canvasBackgroundStyle: CanvasBackgroundStyle
    var canvasBackgroundAnimated: Bool
    var canvasPadding: CGFloat
    var cameraContentMode: CameraContentMode
    var cameraFramePadding: CGFloat
    var cameraShadowEnabled: Bool
    var sourceOpacities: [CaptureSource: CGFloat]

    init(settings: RecordingSettings) {
        self.init(
            enabledSources: settings.visibleSources,
            sceneLayout: settings.sceneLayout,
            screenSourceGeometry: ScreenSourceGeometry(settings: settings),
            cameraCropAmount: settings.cameraCropAmount,
            cameraCropPosition: settings.cameraCropPosition,
            canvasBackgroundStyle: settings.canvasBackgroundStyle,
            canvasBackgroundAnimated: settings.canvasBackgroundAnimated,
            canvasPadding: settings.canvasPadding,
            cameraContentMode: settings.cameraContentMode,
            cameraFramePadding: 0,
            cameraShadowEnabled: settings.cameraShadowEnabled
        )
    }

    init(
        enabledSources: Set<CaptureSource>,
        sceneLayout: SceneLayout,
        screenSourceGeometry: ScreenSourceGeometry = ScreenSourceGeometry(),
        cameraCropAmount: CGPoint = .zero,
        cameraCropPosition: CGPoint = .zero,
        canvasBackgroundStyle: CanvasBackgroundStyle = .black,
        canvasBackgroundAnimated: Bool = false,
        canvasPadding: CGFloat = 0,
        cameraContentMode: CameraContentMode = .fill,
        cameraFramePadding: CGFloat = 0,
        cameraShadowEnabled: Bool = false,
        sourceOpacities: [CaptureSource: CGFloat] = [:]
    ) {
        self.enabledSources = enabledSources
        self.sceneLayout = sceneLayout
        self.screenSourceGeometry = screenSourceGeometry
        self.cameraCropAmount = cameraCropAmount
        self.cameraCropPosition = cameraCropPosition
        self.canvasBackgroundStyle = canvasBackgroundStyle
        self.canvasBackgroundAnimated = canvasBackgroundAnimated
        self.canvasPadding = canvasPadding
        self.cameraContentMode = cameraContentMode
        self.cameraFramePadding = 0
        self.cameraShadowEnabled = cameraShadowEnabled
        self.sourceOpacities = sourceOpacities
    }

    func sourceOpacity(for source: CaptureSource) -> CGFloat {
        guard enabledSources.contains(source) else { return 0 }
        return min(1, max(0, sourceOpacities[source] ?? 1))
    }

    var renderedSources: Set<CaptureSource> {
        let visible = enabledSources.filter { sourceOpacity(for: $0) > 0.001 }
        return visible.isEmpty ? enabledSources : Set(visible)
    }
}

struct ScreenSourceGeometry: Equatable {
    var usesPickedContent: Bool
    var selectedDisplayID: String?
    var normalizedCrop: CGRect?
    var sourceAspectRatio: CGFloat?

    init(
        usesPickedContent: Bool = false,
        selectedDisplayID: String? = nil,
        normalizedCrop: CGRect? = nil,
        sourceAspectRatio: CGFloat? = nil
    ) {
        self.usesPickedContent = usesPickedContent
        self.selectedDisplayID = selectedDisplayID
        self.normalizedCrop = normalizedCrop
        self.sourceAspectRatio = sourceAspectRatio
    }

    init(settings: RecordingSettings, sourceAspectRatio: CGFloat? = nil) {
        self.init(
            usesPickedContent: settings.usesPickedScreenContent,
            selectedDisplayID: settings.selectedDisplayID,
            normalizedCrop: settings.screenCrop,
            sourceAspectRatio: sourceAspectRatio
        )
    }

    func aspectRatio(fallback: CGFloat = SceneLayout.defaultScreenAspectRatio) -> CGFloat {
        if let sourceAspectRatio, sourceAspectRatio > 0 {
            return sourceAspectRatio
        }
        if let normalizedCrop, normalizedCrop.width > 0, normalizedCrop.height > 0 {
            return normalizedCrop.width / normalizedCrop.height
        }
        return fallback
    }

    func sourceRect(in rect: CGRect) -> CGRect {
        guard let normalizedCrop else { return rect }
        let crop = normalizedCrop.standardized
        let x = min(1, max(0, crop.minX))
        let y = min(1, max(0, crop.minY))
        let maxX = min(1, max(x, crop.maxX))
        let maxY = min(1, max(y, crop.maxY))
        return CGRect(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height,
            width: max(2, (maxX - x) * rect.width),
            height: max(2, (maxY - y) * rect.height)
        )
    }
}

enum RecordingSceneTransitionCurve: Equatable {
    case linear
    case easeInOut

    func value(at progress: CGFloat) -> CGFloat {
        let progress = min(1, max(0, progress))
        switch self {
        case .linear:
            return progress
        case .easeInOut:
            return progress * progress * (3 - 2 * progress)
        }
    }
}

struct RecordingSceneTransition: Equatable {
    var duration: TimeInterval
    var curve: RecordingSceneTransitionCurve

    static let cut = RecordingSceneTransition(duration: 0, curve: .linear)
    static let sceneSwitch = RecordingSceneTransition(duration: 0.35, curve: .easeInOut)

    init(duration: TimeInterval, curve: RecordingSceneTransitionCurve = .easeInOut) {
        self.duration = max(0, duration)
        self.curve = curve
    }

    var isCut: Bool {
        duration <= 0
    }

    func progress(elapsed: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        return curve.value(at: CGFloat(elapsed / duration))
    }
}

struct RecordingSceneEvent: Equatable {
    let time: TimeInterval
    let scene: RecordingScene
    let transition: RecordingSceneTransition

    init(
        time: TimeInterval,
        scene: RecordingScene,
        transition: RecordingSceneTransition = .cut
    ) {
        self.time = time
        self.scene = scene
        self.transition = transition
    }
}

extension ScenePreset {
    static func defaultPreset(for layout: CaptureLayout) -> ScenePreset {
        switch layout {
        case .vertical:
            return .screenTop50
        case .horizontal:
            return .cameraInset
        }
    }

    var supportedLayouts: Set<CaptureLayout> {
        switch self {
        case .stackedHalves:
            return [.vertical]
        case .screenTop50:
            return [.vertical]
        case .screenTop70:
            return [.vertical]
        case .cameraInset:
            return [.horizontal]
        case .screenFocus:
            return [.vertical, .horizontal]
        case .screenFullscreen, .webcamFullscreen:
            return [.vertical, .horizontal]
        case .webcamLeft:
            return [.horizontal]
        case .cameraFocus:
            return []
        }
    }

    func supports(_ layout: CaptureLayout) -> Bool {
        supportedLayouts.contains(layout)
    }

    var enablesScreenSource: Bool {
        true
    }
}

struct RecordingSettings {
    static let supportedFrameRates = [24, 30, 60]
    static let minCustomVideoBitrate = 2_000_000
    static let maxCustomVideoBitrate = 80_000_000

    var layout: CaptureLayout = .vertical
    var outputResolution: OutputResolution = .p1080
    var outputVideoFormat: OutputVideoFormat = .mov
    var framesPerSecond: Int = 30
    var customVideoBitrate: Int?
    var audioQuality: AudioQuality = .standard
    var sourceAudioFormat: SourceAudioFormat = .aac
    var microphoneGain: Double = 1.0
    var systemAudioGain: Double = 1.0
    var removesCameraBackgroundAfterRecording: Bool = false
    var savesSourceFiles: Bool = true
    var renamesRecordingsFromSpeech: Bool = false
    var showsRuleOfThirdsOverlay: Bool = false
    var socialSafeZoneOverlay: SocialVideoSafeZone = .none
    var includeCursor: Bool = true
    var enabledSources: Set<CaptureSource> = [.screen, .camera, .microphone]
    var hiddenSources: Set<CaptureSource> = []
    var usesPickedScreenContent: Bool = false
    var screenSourceBinding: ScreenSourceBinding? = .display(id: nil)
    var selectedDisplayID: String?
    var selectedCameraID: String?
    var selectedMicrophoneID: String?
    var trustedRemoteCameraServiceIDs: Set<String> = []
    var remoteCameraSettingsByServiceID: [String: RemoteCameraSettings] = [:]
    var screenCrop: CGRect?
    var cameraCropAmount: CGPoint = .zero
    var cameraCropPosition: CGPoint = .zero
    var canvasBackgroundStyle: CanvasBackgroundStyle = .black
    var canvasBackgroundAnimated: Bool = false
    var canvasPadding: CGFloat = 0
    var cameraContentMode: CameraContentMode = .fill
    var cameraFramePadding: CGFloat = 0
    var cameraShadowEnabled: Bool = false
    var sceneLayout = SceneLayout()
    var selectedScenePreset: ScenePreset?
    var outputDirectoryBookmarkData: Data?
    var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies", isDirectory: true)
        .appendingPathComponent("BlitzRecorder", isDirectory: true)

    var autoVideoBitrate: Int {
        SocialVideoEncoding.videoBitrate(
            resolution: outputResolution,
            fps: framesPerSecond
        )
    }

    var screenBitrate: Int {
        let base = SocialVideoEncoding.screenIntermediateBitrate(
            resolution: outputResolution,
            layout: layout,
            fps: framesPerSecond
        )
        return Int(Double(base) * intermediateVideoBoost)
    }

    var cameraBitrate: Int {
        let base = SocialVideoEncoding.cameraIntermediateBitrate(
            resolution: outputResolution,
            fps: framesPerSecond
        )
        return Int(Double(base) * intermediateVideoBoost)
    }

    var finalVideoBitrate: Int {
        guard let customVideoBitrate else { return autoVideoBitrate }
        return min(
            RecordingSettings.maxCustomVideoBitrate,
            max(RecordingSettings.minCustomVideoBitrate, customVideoBitrate)
        )
    }

    var finalAudioBitrate: Int {
        audioQuality.bitrate
    }

    var effectiveSourceAudioFormat: SourceAudioFormat {
        savesSourceFiles ? sourceAudioFormat : .aac
    }

    var sourceVideoFormat: OutputVideoFormat {
        savesSourceFiles ? .mov : outputVideoFormat
    }

    private var intermediateVideoBoost: Double {
        guard customVideoBitrate != nil else { return 1.0 }
        let boost = Double(finalVideoBitrate) / Double(autoVideoBitrate)
        return min(2.5, max(0.5, boost))
    }

    var visibleSources: Set<CaptureSource> {
        enabledSources.subtracting(hiddenSources)
    }
}

struct RecordingTake {
    let scratchDirectory: URL
    let screenURL: URL
    let cameraURL: URL
    let audioURL: URL
    let systemAudioURL: URL
    let transcriptURL: URL
    let finalVideoURL: URL
    let outputVideoFormat: OutputVideoFormat
    let titleSlug: String?

    var sourceManifestURL: URL {
        scratchDirectory.appendingPathComponent("take.json")
    }

    var projectURL: URL {
        scratchDirectory.appendingPathComponent("project.blitzrecorder.json")
    }
}
