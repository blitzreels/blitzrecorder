import Foundation

extension RecorderViewModel {
    func setLayout(_ layout: CaptureLayout) {
        cancelScreenSplitPreview()
        cancelSideSplitPreview()
        coordinator.setLayout(layout)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func selectScene(_ id: UUID) {
        cancelScreenSplitPreview()
        cancelSideSplitPreview()
        coordinator.selectScene(id: id)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func selectSceneAcrossLayouts(_ id: UUID) {
        cancelScreenSplitPreview()
        cancelSideSplitPreview()
        if let target = coordinator.layout(ofSceneID: id), target != settings.layout {
            coordinator.setLayout(target)
        }
        coordinator.selectScene(id: id)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    var canSwitchScene: Bool {
        coordinator.allowsSceneChanges
    }

    var currentScenes: [RecordingSceneDefinition] {
        _ = sceneLibraryRevision
        return coordinator.scenesForCurrentLayout()
    }

    var allScenes: [RecordingSceneDefinition] {
        _ = sceneLibraryRevision
        let current = coordinator.scenesForCurrentLayout()
        let others = CaptureLayout.allCases
            .filter { $0 != settings.layout }
            .flatMap { coordinator.scenes(for: $0) }
        return current + others
    }

    var selectedSceneID: UUID? {
        _ = sceneLibraryRevision
        return coordinator.selectedSceneIDForCurrentLayout()
    }

    var selectedScenePreset: ScenePreset? {
        currentScenes.first { $0.id == selectedSceneID }?.snapshot.selectedScenePreset
    }

    var selectedSceneName: String {
        guard let scene = currentScenes.first(where: { $0.id == selectedSceneID }) else { return "Scene" }
        return sceneLabel(scene)
    }

    func sceneLayout(_ scene: RecordingSceneDefinition) -> SceneLayout {
        scene.id == selectedSceneID ? settings.sceneLayout : scene.snapshot.sceneLayout
    }

    func sceneVisibleSources(_ scene: RecordingSceneDefinition) -> Set<CaptureSource> {
        settings.enabledSources
            .intersection([.screen, .camera])
            .subtracting(scene.snapshot.hiddenVideoSources)
    }

    /// Names the camera by number once a second camera exists: "Screen + Camera 2".
    func sceneLabel(_ scene: RecordingSceneDefinition) -> String {
        let name = sceneLayout(scene).arrangementName(visibleSources: sceneVisibleSources(scene))
        guard !settings.extraCameraAngleIDs.isEmpty,
              sceneLayout(scene).secondCameraFrame == nil,
              let number = CameraFeeds.angleNumber(role: scene.snapshot.cameraFeeds.camera) else { return name }
        return name.replacingOccurrences(of: "Camera", with: "Camera \(number)")
    }

}
