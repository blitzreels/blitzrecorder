import CoreGraphics
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
        let previousSettings = settings
        saveCurrentSceneSnapshotIfNeeded()
        guard let scene = sceneLibrary.selectScene(id: id, layout: settings.layout) else { return }
        saveSceneLibrary()
        let screenSelection = currentScreenSourceSelection()
        let screenAspectRatio = settings.screenSourceAspectRatio
        applySceneSnapshot(scene.snapshot)
        restoreScreenSourceSelection(screenSelection)
        settings.screenSourceAspectRatio = screenAspectRatio
        carryCameraFraming(from: previousSettings)
        persist(saveSceneSnapshot: false)
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if state == .idle {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
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
        let previousSettings = settings
        saveCurrentSceneSnapshotIfNeeded()
        settings.layout = layout
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
        carryCameraFraming(from: previousSettings)
        saveSceneLibrary()
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func carryCameraFraming(from previous: RecordingSettings) {
        func showsCamera(_ settings: RecordingSettings) -> Bool {
            settings.enabledSources.contains(.camera)
                && !settings.hiddenSources.contains(.camera)
                && settings.cameraContentMode == .fill
        }
        guard showsCamera(previous), showsCamera(settings) else { return }
        func canvasRect(_ frame: CGRect, layout: CaptureLayout) -> CGRect {
            CGRect(
                x: frame.minX * layout.aspectRatio,
                y: frame.minY,
                width: frame.width * layout.aspectRatio,
                height: frame.height
            )
        }
        let transferred = SourceCropGeometry.transferredCrop(.init(
            amount: previous.cameraCropAmount,
            position: previous.cameraCropPosition,
            fromTarget: canvasRect(previous.sceneLayout.cameraFrame, layout: previous.layout),
            toTarget: canvasRect(settings.sceneLayout.cameraFrame, layout: settings.layout),
            sourceAspectRatio: cameraAspectRatio()
        ))
        settings.cameraCropAmount = transferred.amount
        settings.cameraCropPosition = transferred.position
    }
}
