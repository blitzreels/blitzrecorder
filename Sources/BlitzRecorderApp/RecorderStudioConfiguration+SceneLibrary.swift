import Foundation

@MainActor
extension RecorderStudioConfiguration {
    func scenesForCurrentLayout() -> [RecordingSceneDefinition] {
        sceneLibrary.scenes(for: settings.layout)
    }

    func scenes(for layout: CaptureLayout) -> [RecordingSceneDefinition] {
        sceneLibrary.scenes(for: layout)
    }

    func layout(ofSceneID id: UUID) -> CaptureLayout? {
        sceneLibrary.layout(ofSceneID: id)
    }

    func selectedSceneIDForCurrentLayout() -> UUID? {
        sceneLibrary.selectedSceneIDsByLayout[settings.layout]
    }

    func selectedSceneName() -> String {
        sceneLibrary.selectedScene(layout: settings.layout)?.name ?? "Scene"
    }

    func selectScene(id: UUID) {
        guard allowsSceneChanges else {
            onMessage?("Scenes are locked while saving.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        guard let scene = sceneLibrary.selectScene(id: id, layout: settings.layout) else { return }
        saveSceneLibrary()
        let screenSelection = currentScreenSourceSelection()
        let screenAspectRatio = settings.screenSourceAspectRatio
        applySceneSnapshot(scene.snapshot)
        restoreScreenSourceSelection(screenSelection)
        settings.screenSourceAspectRatio = screenAspectRatio
        persist(saveSceneSnapshot: false)
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if state == .idle {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    func createSceneFromCurrentSettings(named name: String? = nil) {
        guard sceneLibraryEditingIsAllowed() else { return }
        saveCurrentSceneSnapshotIfNeeded()
        let snapshot = currentRecordingSceneSnapshot()
        let scene = sceneLibrary.createScene(
            layout: settings.layout,
            name: name ?? RecordingSceneDefinition.defaultName(for: settings),
            snapshot: snapshot
        )
        saveSceneLibrary()
        applySceneSnapshot(scene.snapshot)
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func duplicateSelectedScene() {
        guard sceneLibraryEditingIsAllowed() else { return }
        saveCurrentSceneSnapshotIfNeeded()
        guard let selectedSceneID = sceneLibrary.selectedSceneIDsByLayout[settings.layout],
              let scene = sceneLibrary.duplicateScene(id: selectedSceneID, layout: settings.layout) else {
            return
        }
        saveSceneLibrary()
        applySceneSnapshot(scene.snapshot)
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func renameScene(id: UUID, to name: String) {
        guard sceneLibraryEditingIsAllowed() else { return }
        guard sceneLibrary.renameScene(id: id, layout: settings.layout, name: name) else {
            return
        }
        saveSceneLibrary()
    }

    func deleteScene(id: UUID) {
        guard sceneLibraryEditingIsAllowed() else { return }
        guard sceneLibrary.deleteScene(id: id, layout: settings.layout) else {
            onMessage?("Keep at least one scene in this canvas format.")
            return
        }
        saveSceneLibrary()
        if let selectedScene = sceneLibrary.selectedScene(layout: settings.layout) {
            applySceneSnapshot(selectedScene.snapshot)
            persist(saveSceneSnapshot: false)
            onScreenCaptureConfigurationChanged?()
            onCameraConfigurationChanged?()
        }
    }

    func moveScene(id: UUID, to index: Int) {
        guard sceneLibraryEditingIsAllowed() else { return }
        guard sceneLibrary.moveScene(id: id, layout: settings.layout, to: index) else {
            return
        }
        saveSceneLibrary()
    }

    func setLayout(_ layout: CaptureLayout) {
        guard state == .idle else {
            onMessage?("Output aspect ratio is locked while recording.")
            return
        }
        guard settings.layout != layout else {
            if let next = RecordingSceneMutation.clearingIncompatibleScreenCrop(settings) {
                settings = next
                persist()
                onScreenCaptureConfigurationChanged?()
            }
            return
        }
        let preservedScreenSource = currentScreenSourceSelection()
        saveCurrentSceneSnapshotIfNeeded()
        settings.layout = layout
        sceneLibrary.ensureScenes(for: layout)
        if let scene = sceneLibrary.selectedScene(layout: layout) {
            applySceneSnapshot(scene.snapshot)
        } else {
            settings.screenCrop = nil
            let layoutDefaults = RecordingSceneMutation.defaultsForLayout(
                layout,
                screenAspectRatio: screenAspectRatio(),
                cameraAspectRatio: cameraAspectRatio()
            )
            settings.selectedScenePreset = layoutDefaults.preset
            settings.sceneLayout = layoutDefaults.layout
        }
        restoreScreenSourceSelection(preservedScreenSource)
        recomputeSelectedPresetLayoutForCurrentSource()
        saveSceneLibrary()
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    private func sceneLibraryEditingIsAllowed() -> Bool {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return false
        }
        return true
    }
}
