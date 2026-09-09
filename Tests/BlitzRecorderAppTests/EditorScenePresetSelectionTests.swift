import XCTest

@testable import BlitzRecorderApp

final class EditorScenePresetSelectionTests: XCTestCase {
    func testHiddenCameraSelectsScreenOnlyEvenWithAnInsetLayout() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone]
        var scene = RecordingScene(settings: settings)
        scene.sceneLayout = SceneLayout.presetLayout(.cameraInset, for: .horizontal)
        scene.sourceOpacities[.camera] = 0

        XCTAssertTrue(
            EditorScenePresetSelection.isSelected(
                .init(
                    preset: .screenFullscreen,
                    scene: scene,
                    layout: SceneLayout.presetLayout(.screenFullscreen, for: .horizontal)
                )))
        XCTAssertFalse(
            EditorScenePresetSelection.isSelected(
                .init(
                    preset: .cameraInset, scene: scene, layout: scene.sceneLayout
                )))
    }

    func testCameraOnlyDoesNotSelectScreenOnly() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera, .microphone]
        let scene = RecordingScene(settings: settings)

        XCTAssertTrue(
            EditorScenePresetSelection.isSelected(
                .init(
                    preset: .webcamFullscreen, scene: scene, layout: scene.sceneLayout
                )))
        XCTAssertFalse(
            EditorScenePresetSelection.isSelected(
                .init(
                    preset: .screenFullscreen, scene: scene, layout: scene.sceneLayout
                )))
    }

    func testVisibleSourcesAndLayoutBothDetermineCombinedPreset() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        var scene = RecordingScene(settings: settings)
        scene.sceneLayout = SceneLayout.presetLayout(.cameraInset, for: .horizontal)

        XCTAssertTrue(
            EditorScenePresetSelection.isSelected(
                .init(
                    preset: .cameraInset, scene: scene, layout: scene.sceneLayout
                )))
        XCTAssertFalse(
            EditorScenePresetSelection.isSelected(
                .init(
                    preset: .webcamLeft,
                    scene: scene,
                    layout: SceneLayout.presetLayout(.webcamLeft, for: .horizontal)
                )))
    }
}
