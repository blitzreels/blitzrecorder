import Foundation

enum ScenePreset: String, CaseIterable {
    case stackedHalves = "Stacked"
    case screenTop50 = "Screen 50%"
    case screenTop70 = "Screen 70%"
    case screenFocus = "Screen Focus"
    case cameraInset = "Camera Inset"
    case cameraFocus = "Camera Focus"
    case webcamLeft = "Webcam Left"
    case cameraRight = "Camera Right"
    case equalSplit = "Equal Split"
    case screenInset = "Screen Inset"
    case screenFullscreen = "Screen Fullscreen"
    case webcamFullscreen = "Webcam Fullscreen"
    /// Camera 1 and Camera 2 side by side; offered once a second camera is added.
    case twoCameras = "Two Cameras"
    /// The screen with Camera 1 and Camera 2 next to it; offered once a second camera is added.
    case twoCamerasScreen = "Two Cameras + Screen"

    /// Presets that need a camera angle, and the scene names that need no "Camera N" numbering.
    static let twoCameraPresets: [ScenePreset] = [.twoCameras, .twoCamerasScreen]

    var needsSecondCamera: Bool { Self.twoCameraPresets.contains(self) }

    static var allCases: [ScenePreset] {
        [
            .screenTop50,
            .cameraInset,
            .webcamLeft,
            .cameraRight,
            .equalSplit,
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
            return "Camera inset"
        case .cameraFocus:
            return "Speaker main"
        case .webcamLeft:
            return "Side by side"
        case .cameraRight:
            return "Camera right"
        case .equalSplit:
            return "Equal split"
        case .screenInset:
            return "Screen inset"
        case .screenFullscreen:
            return "Screen 100%"
        case .webcamFullscreen:
            return "Camera 100%"
        case .twoCameras:
            return "Two cameras"
        case .twoCamerasScreen:
            return "Screen + two cameras"
        }
    }
}

extension ScenePreset {
    static func defaultPreset(for layout: CaptureLayout) -> ScenePreset {
        switch layout {
        case .vertical:
            return .screenTop50
        case .horizontal, .square:
            return .webcamLeft
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
        case .cameraInset, .screenInset:
            return [.vertical, .horizontal, .square]
        case .screenFocus:
            return [.vertical, .horizontal, .square]
        case .screenFullscreen, .webcamFullscreen, .twoCameras, .twoCamerasScreen:
            return [.vertical, .horizontal, .square]
        case .webcamLeft, .cameraRight, .equalSplit:
            return [.horizontal, .square]
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

    var requiredVideoSources: Set<CaptureSource> {
        switch self {
        case .screenFullscreen: [.screen]
        case .webcamFullscreen, .twoCameras: [.camera]
        default: [.screen, .camera]
        }
    }
}
