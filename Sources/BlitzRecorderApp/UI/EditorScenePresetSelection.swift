enum EditorScenePresetSelection {
    struct Request {
        let preset: ScenePreset
        let scene: RecordingScene
        let layout: SceneLayout
    }

    static func isSelected(_ request: Request) -> Bool {
        let videoSources = request.scene.renderedSources.intersection([.screen, .camera])
        switch request.preset {
        case .screenFullscreen:
            return videoSources == [.screen]
        case .webcamFullscreen:
            return videoSources == [.camera]
        default:
            return videoSources == [.screen, .camera] && request.scene.sceneLayout == request.layout
        }
    }
}
