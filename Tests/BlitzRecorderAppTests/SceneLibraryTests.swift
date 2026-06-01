import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class SceneLibraryTests: XCTestCase {
    func testDefaultLibrarySeedsCurrentSceneFromExistingSettings() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.3, width: 1, height: 0.7)
        settings.sceneLayout.cameraFrame = CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.22)

        let library = SceneLibrary.defaultLibrary(currentSettings: settings)
        let selected = library.selectedScene(layout: .vertical)

        XCTAssertEqual(selected?.name, "Screen + Cam")
        XCTAssertEqual(selected?.snapshot.sceneLayout.screenFrame, settings.sceneLayout.screenFrame)
        XCTAssertEqual(selected?.snapshot.sceneLayout.cameraFrame, settings.sceneLayout.cameraFrame)
    }

    func testCoordinatorRestoresLastScenePerCanvasFormat() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let horizontalSceneID = coordinator.sceneLibrary.scenes(for: .horizontal)[1].id

        coordinator.setLayout(.horizontal)
        coordinator.selectScene(id: horizontalSceneID)
        coordinator.setLayout(.vertical)
        coordinator.setLayout(.horizontal)

        XCTAssertEqual(coordinator.selectedSceneIDForCurrentLayout(), horizontalSceneID)
        XCTAssertEqual(coordinator.settings.layout, .horizontal)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzrecorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
