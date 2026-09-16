import Foundation

extension RecorderViewModel {
    func setLayout(_ layout: CaptureLayout) {
        cancelScreenSplitPreview()
        coordinator.setLayout(layout)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func selectScene(_ id: UUID) {
        cancelScreenSplitPreview()
        coordinator.selectScene(id: id)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func selectSceneAcrossLayouts(_ id: UUID) {
        cancelScreenSplitPreview()
        if let target = coordinator.layout(ofSceneID: id), target != settings.layout {
            coordinator.setLayout(target)
        }
        coordinator.selectScene(id: id)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func createScene() {
        cancelScreenSplitPreview()
        coordinator.createSceneFromCurrentSettings()
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func duplicateSelectedScene() {
        cancelScreenSplitPreview()
        coordinator.duplicateSelectedScene()
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func renameScene(_ id: UUID, to name: String) {
        coordinator.renameScene(id: id, to: name)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func deleteScene(_ id: UUID) {
        coordinator.deleteScene(id: id)
        sceneLibraryRevision += 1
        syncSettingsAfterSceneChange()
    }

    func moveScene(_ id: UUID, direction: SceneMoveDirection) {
        guard let currentIndex = currentScenes.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = currentIndex - 1
        case .down:
            targetIndex = currentIndex + 1
        }
        coordinator.moveScene(id: id, to: targetIndex)
        sceneLibraryRevision += 1
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

    var selectedSceneName: String {
        _ = sceneLibraryRevision
        return coordinator.selectedSceneName()
    }

}
