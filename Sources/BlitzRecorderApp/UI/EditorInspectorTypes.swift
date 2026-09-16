import Foundation

enum EditorInspectorTab: String, CaseIterable {
    case layout = "Layout"
    case text = "Text"
    case zoom = "Motion"
    case silence = "Silence"
    case privacy = "Privacy"
    case audio = "Audio"
    case blitzReels = "BlitzReels"

    var systemImage: String {
        switch self {
        case .layout: return BlitzSymbols.layout
        case .text: return "textformat"
        case .zoom: return "cursorarrow.motionlines"
        case .silence: return "waveform.path"
        case .privacy: return "eye.slash"
        case .audio: return "waveform"
        case .blitzReels: return "arrow.up.right"
        }
    }
}

struct EditorExportPresetRequest {
    let preset: ExportPerformancePreset
    let project: RecordingProject
}

enum EditorCameraInsetControlChange {
    case alignment(CameraInsetAlignment)
    case shape(CameraInsetShape)
    case size(CGFloat)
}

enum EditorScenePresetSourceCorrection {
    static func correction(for preset: ScenePreset) -> RecordingProjectSceneCorrection? {
        switch preset {
        case .screenFullscreen:
            return .screenOnly
        case .webcamFullscreen:
            return .cameraOnly
        default:
            return nil
        }
    }
}
