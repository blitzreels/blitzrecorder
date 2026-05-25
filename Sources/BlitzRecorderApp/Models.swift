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

enum ScenePreset: String, CaseIterable {
    case stackedHalves = "Stacked"
    case screenFocus = "Screen Focus"
    case cameraInset = "Camera Inset"
    case cameraFocus = "Camera Focus"
    case webcamFullscreen = "Webcam Fullscreen"

    var detail: String {
        switch self {
        case .stackedHalves:
            return "Screen top"
        case .screenFocus:
            return "Screen crop"
        case .cameraInset:
            return "Cam corner"
        case .cameraFocus:
            return "Speaker main"
        case .webcamFullscreen:
            return "Webcam 100%"
        }
    }
}

enum CanvasBackgroundStyle: String, CaseIterable {
    case black = "black"
    case graphite = "graphite"
    case aurora = "aurora"
    case ocean = "ocean"
    case sunset = "sunset"
    case silver = "silver"

    var displayName: String {
        switch self {
        case .black:
            return "Black"
        case .graphite:
            return "Titanium"
        case .aurora:
            return "Aurora"
        case .ocean:
            return "Lagoon"
        case .sunset:
            return "Ember"
        case .silver:
            return "Liquid Silver"
        }
    }
}

struct SourceOption: Equatable {
    let id: String
    let name: String
}

struct SceneLayout: Equatable {
    // Frames are normalized in the preview canvas coordinate space: origin at bottom-left.
    // layerOrder is back-to-front, so the last layer is visually on top.
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
            sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
            return sceneLayout
        case .screenFocus:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.08, y: 0.045, width: 0.84, height: 0.24)
            )
            return sceneLayout
        case .cameraInset:
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0, y: 0.035, width: 1, height: 0.34)
            )
            return sceneLayout
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
            var sceneLayout = SceneLayout()
            sceneLayout.screenFrame = canvasFillingFrame(sourceAspectRatio: screenAspectRatio, canvasAspectRatio: canvasAR)
            sceneLayout.cameraFrame = fittedSourceFrame(
                sourceAspectRatio: cameraAspectRatio,
                canvasAspectRatio: canvasAR,
                in: CGRect(x: 0.685, y: 0.035, width: 0.28, height: 0.28)
            )
            return sceneLayout
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

    /// Canvas-normalized frame for a source that fills the canvas at its native aspect ratio,
    /// extending past the canvas in whichever dimension can't fit. Centered.
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

    func frame(for kind: SceneLayerKind) -> CGRect {
        switch kind {
        case .screen:
            return screenFrame
        case .camera:
            return cameraFrame
        }
    }
}

struct RecordingScene: Equatable {
    var enabledSources: Set<CaptureSource>
    var sceneLayout: SceneLayout
    var cameraCropAmount: CGPoint
    var cameraCropPosition: CGPoint
    var canvasBackgroundStyle: CanvasBackgroundStyle
    var canvasPadding: CGFloat

    init(settings: RecordingSettings) {
        enabledSources = settings.enabledSources
        sceneLayout = settings.sceneLayout
        cameraCropAmount = settings.cameraCropAmount
        cameraCropPosition = settings.cameraCropPosition
        canvasBackgroundStyle = settings.canvasBackgroundStyle
        canvasPadding = settings.canvasPadding
    }
}

struct RecordingSceneEvent: Equatable {
    let time: TimeInterval
    let scene: RecordingScene
}

extension ScenePreset {
    static func defaultPreset(for layout: CaptureLayout) -> ScenePreset {
        switch layout {
        case .vertical:
            return .stackedHalves
        case .horizontal:
            return .cameraInset
        }
    }

    var supportedLayouts: Set<CaptureLayout> {
        switch self {
        case .stackedHalves:
            return [.vertical]
        case .cameraInset:
            return [.horizontal]
        case .screenFocus:
            return [.vertical, .horizontal]
        case .cameraFocus:
            return [.horizontal]
        case .webcamFullscreen:
            return [.vertical, .horizontal]
        }
    }

    func supports(_ layout: CaptureLayout) -> Bool {
        supportedLayouts.contains(layout)
    }
}

struct RecordingSettings {
    static let supportedFrameRates = [24, 30, 60]

    var layout: CaptureLayout = .vertical
    var outputResolution: OutputResolution = .p1080
    var outputVideoFormat: OutputVideoFormat = .mov
    var framesPerSecond: Int = 60
    var microphoneGain: Double = 1.0
    var systemAudioGain: Double = 1.0
    var removesCameraBackgroundAfterRecording: Bool = false
    var savesSourceFiles: Bool = false
    var showsRuleOfThirdsOverlay: Bool = false
    var socialSafeZoneOverlay: SocialVideoSafeZone = .none
    var includeCursor: Bool = true
    var enabledSources: Set<CaptureSource> = [.screen, .camera, .microphone]
    var hiddenSources: Set<CaptureSource> = []
    var usesPickedScreenContent: Bool = false
    var selectedDisplayID: String?
    var selectedCameraID: String?
    var selectedMicrophoneID: String?
    var trustedRemoteCameraServiceIDs: Set<String> = []
    var remoteCameraSettingsByServiceID: [String: RemoteCameraSettings] = [:]
    var screenCrop: CGRect?
    var cameraCropAmount: CGPoint = .zero
    var cameraCropPosition: CGPoint = .zero
    var canvasBackgroundStyle: CanvasBackgroundStyle = .black
    var canvasPadding: CGFloat = 0
    var sceneLayout = SceneLayout()
    var selectedScenePreset: ScenePreset?
    var outputDirectoryBookmarkData: Data?
    var outputDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies", isDirectory: true)
        .appendingPathComponent("BlitzRecorder", isDirectory: true)

    var screenBitrate: Int {
        let baseline = layout == .vertical ? 16_000_000 : 20_000_000
        return Int(Double(baseline) * outputResolution.bitrateScale(for: layout))
    }

    var cameraBitrate: Int {
        16_000_000
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
}
