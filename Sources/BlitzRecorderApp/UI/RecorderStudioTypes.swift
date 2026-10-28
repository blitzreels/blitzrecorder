import Foundation

enum SourceSelection: CaseIterable, Equatable {
    case screen
    case camera
    case microphone
    case systemAudio

    init(source: CaptureSource) {
        switch source {
        case .screen:
            self = .screen
        case .camera:
            self = .camera
        case .microphone:
            self = .microphone
        case .systemAudio:
            self = .systemAudio
        }
    }

    var source: CaptureSource {
        switch self {
        case .screen:
            return .screen
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .systemAudio:
            return .systemAudio
        }
    }
}

enum RecorderInspectorSelection: Hashable {
    case source(CaptureSource)
    /// Camera 2 in a two-camera scene; its input is still the camera source.
    case secondCamera
    case canvas
    case layout

    static func initial(settings: RecordingSettings) -> RecorderInspectorSelection {
        let visibleSources = settings.visibleSources
        if let layer = SceneLayoutProjection
            .frontToBackOrder(for: settings.sceneLayout)
            .first(where: { visibleSources.contains($0.source) }) {
            return .source(layer.source)
        }
        if let source = CaptureSource.allCases.first(where: visibleSources.contains) {
            return .source(source)
        }
        return .canvas
    }

    var source: CaptureSource? {
        switch self {
        case .source(let source): source
        case .secondCamera: .camera
        case .canvas, .layout: nil
        }
    }

    var sceneLayer: SceneLayerKind? {
        if self == .secondCamera { return .secondCamera }
        switch source {
        case .screen:
            return .screen
        case .camera:
            return .camera
        case .microphone, .systemAudio, .none:
            return nil
        }
    }
}

enum ScreenCaptureAreaSelection: Equatable {
    case fullDisplay
    case activeWindow
    case manualCrop
}

enum RecorderStudioMode: Equatable {
    case record
    case projects
    case edit

    var keepsIdleCaptureResourcesActive: Bool { self == .record }
}

struct ScheduledTargetWindowFitContext: Equatable {
    let areaSelection: ScreenCaptureAreaSelection
    let screenSourceBinding: ScreenSourceBinding?
    let usesPickedScreenContent: Bool
    let sceneID: UUID?
    let layout: CaptureLayout
    let screenFrame: CGRect
    let canvasPadding: CGFloat
}

struct EditorProjectSceneCorrectionRequest {
    let eventIndex: Int
    let correction: RecordingProjectSceneCorrection
}

struct EditorProjectStateUpdateRequest {
    let editorState: RecordingProject.EditorStateSnapshot
    let actionName: String
}

enum RecorderStudioEditPolicy {
    static func canEdit(state: RecordingState) -> Bool {
        switch state {
        case .idle, .recording, .paused:
            return true
        case .starting, .finishing:
            return false
        }
    }

    static func idleStatus(
        state: RecordingState,
        lastExportedURL: URL?,
        detailMessage: String
    ) -> String? {
        guard state == .idle,
              lastExportedURL == nil,
              !detailMessage.isEmpty,
              !detailMessage.hasPrefix("Saved:") else {
            return nil
        }
        return detailMessage
    }
}
