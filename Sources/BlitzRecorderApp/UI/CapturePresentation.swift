import Foundation

extension CaptureSource {
    var symbolName: String {
        switch self {
        case .screen: return BlitzSymbols.screen
        case .camera: return BlitzSymbols.camera
        case .systemAudio: return BlitzSymbols.systemAudio
        case .microphone: return BlitzSymbols.microphone
        }
    }

    var shortLabel: String {
        switch self {
        case .screen: return "Screen"
        case .camera: return "Camera"
        case .systemAudio: return "Mac Audio"
        case .microphone: return "Mic"
        }
    }

    var onboardingPurpose: String {
        switch self {
        case .screen: return "Capture what's on your display."
        case .camera: return "Add your camera to the recording."
        case .systemAudio: return "Record sound playing on your Mac."
        case .microphone: return "Record your voice."
        }
    }

    var isAudioSource: Bool {
        self == .microphone || self == .systemAudio
    }
}

extension ScreenSourceBinding {
    func matches(applicationBinding: ScreenSourceBinding) -> Bool {
        guard kind == .window,
              applicationBinding.kind == .application else {
            return false
        }
        if let processID,
           let applicationProcessID = applicationBinding.processID,
           processID == applicationProcessID {
            return true
        }
        if let bundleIdentifier,
           let applicationBundleIdentifier = applicationBinding.bundleIdentifier,
           bundleIdentifier == applicationBundleIdentifier {
            return true
        }
        if let applicationName,
           let selectedApplicationName = applicationBinding.applicationName,
           applicationName == selectedApplicationName {
            return true
        }
        return false
    }
}

enum SceneMoveDirection {
    case up
    case down
}

extension CaptureLayout {
    var symbolName: String {
        switch self {
        case .vertical: return "rectangle.portrait"
        case .horizontal: return "rectangle"
        case .square: return "square"
        }
    }

    var shortLabel: String {
        switch self {
        case .vertical: return "9:16"
        case .horizontal: return "16:9"
        case .square: return "1:1"
        }
    }

    var titleLabel: String {
        switch self {
        case .vertical: return "Shorts"
        case .horizontal: return "YouTube"
        case .square: return "Square"
        }
    }
}

extension ScenePreset {
    var symbolName: String {
        switch self {
        case .stackedHalves: return BlitzSymbols.split
        case .screenTop50: return BlitzSymbols.split
        case .screenTop70: return BlitzSymbols.split
        case .screenFocus: return "rectangle.inset.filled"
        case .cameraInset: return BlitzSymbols.pictureInPicture
        case .cameraFocus: return "person.crop.rectangle"
        case .webcamLeft: return BlitzSymbols.layout
        case .screenFullscreen: return BlitzSymbols.screen
        case .webcamFullscreen: return BlitzSymbols.camera
        }
    }
}

struct EditorTimelineEditsChange {
    let edits: TimelineEdits
    let actionName: String
}
