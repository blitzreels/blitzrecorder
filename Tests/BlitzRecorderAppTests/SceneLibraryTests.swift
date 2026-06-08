import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class SceneLibraryTests: XCTestCase {
    func testDefaultLibrarySeedsCurrentSceneFromExistingSettings() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.selectedScenePreset = nil
        settings.canvasBackgroundAnimated = true
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.3, width: 1, height: 0.7)
        settings.sceneLayout.cameraFrame = CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.22)

        let library = SceneLibrary.defaultLibrary(currentSettings: settings)
        let selected = library.selectedScene(layout: .vertical)

        XCTAssertEqual(selected?.name, "Screen + Cam")
        XCTAssertEqual(selected?.snapshot.canvasBackgroundAnimated, true)
        XCTAssertEqual(selected?.snapshot.sceneLayout.screenFrame, settings.sceneLayout.screenFrame)
        XCTAssertEqual(selected?.snapshot.sceneLayout.cameraFrame, settings.sceneLayout.cameraFrame)
    }

    func testSceneSnapshotDecodesMissingCanvasBackgroundAnimatedAsFalse() throws {
        var settings = RecordingSettings()
        settings.canvasBackgroundAnimated = true
        let snapshot = RecordingSceneSnapshot(settings: settings)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        payload.removeValue(forKey: "canvasBackgroundAnimated")

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(RecordingSceneSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.canvasBackgroundAnimated, false)
    }

    func testSceneSnapshotPersistsScreenSourceBinding() throws {
        var settings = RecordingSettings()
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .window,
            displayID: "2",
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            processID: 77,
            windowID: 991,
            windowTitle: "Demo"
        )

        let snapshot = RecordingSceneSnapshot(settings: settings)
        let decoded = try JSONDecoder().decode(
            RecordingSceneSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.screenSourceBinding, settings.screenSourceBinding)
    }

    func testSceneSnapshotDecodesMissingScreenSourceBindingAsDisplayBinding() throws {
        var settings = RecordingSettings()
        settings.selectedDisplayID = "42"
        let snapshot = RecordingSceneSnapshot(settings: settings)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        payload.removeValue(forKey: "screenSourceBinding")

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(RecordingSceneSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.screenSourceBinding, .display(id: "42"))
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

    func testCoordinatorSceneSwitchPreservesCurrentCameraDeviceAndCrop() {
        let defaults = temporaryDefaults()
        var currentSettings = RecordingSettings()
        currentSettings.layout = .vertical
        currentSettings.selectedCameraID = "current-camera"
        currentSettings.cameraCropAmount = CGPoint(x: 0.22, y: 0.11)
        currentSettings.cameraCropPosition = CGPoint(x: -0.18, y: 0.31)
        RecordingSettingsStore.save(currentSettings, defaults: defaults)

        var currentSceneSettings = currentSettings
        currentSceneSettings.sceneLayout.cameraFrame = CGRect(x: 0.06, y: 0.62, width: 0.34, height: 0.25)
        var staleSceneSettings = currentSettings
        staleSceneSettings.selectedCameraID = "stale-camera"
        staleSceneSettings.cameraCropAmount = .zero
        staleSceneSettings.cameraCropPosition = .zero
        staleSceneSettings.sceneLayout.cameraFrame = CGRect(x: 0.58, y: 0.08, width: 0.32, height: 0.24)

        let currentScene = RecordingSceneDefinition(
            name: "Current",
            layout: .vertical,
            snapshot: RecordingSceneSnapshot(settings: currentSceneSettings)
        )
        let staleScene = RecordingSceneDefinition(
            name: "Stale",
            layout: .vertical,
            snapshot: RecordingSceneSnapshot(settings: staleSceneSettings)
        )
        let library = SceneLibrary(
            scenesByLayout: [.vertical: [currentScene, staleScene]],
            selectedSceneIDsByLayout: [.vertical: currentScene.id]
        )
        SceneLibraryStore.save(library, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.selectScene(id: staleScene.id)

        XCTAssertEqual(coordinator.settings.sceneLayout.cameraFrame, staleSceneSettings.sceneLayout.cameraFrame)
        XCTAssertEqual(coordinator.settings.selectedCameraID, "current-camera")
        XCTAssertEqual(coordinator.settings.cameraCropAmount, CGPoint(x: 0.22, y: 0.11))
        XCTAssertEqual(coordinator.settings.cameraCropPosition, CGPoint(x: -0.18, y: 0.31))
    }

    func testSceneLibraryCreatesDuplicateRenamesReordersAndDeletesScenes() {
        var settings = RecordingSettings()
        settings.layout = .vertical
        let snapshot = RecordingSceneSnapshot(settings: settings)
        var library = SceneLibrary.defaultLibrary(currentSettings: settings)

        let created = library.createScene(layout: .vertical, name: "Demo", snapshot: snapshot)
        XCTAssertEqual(library.selectedScene(layout: .vertical)?.id, created.id)
        XCTAssertEqual(library.scenes(for: .vertical).last?.name, "Demo")

        let duplicate = library.duplicateScene(id: created.id, layout: .vertical)
        XCTAssertEqual(duplicate?.name, "Demo Copy")
        XCTAssertEqual(library.selectedScene(layout: .vertical)?.id, duplicate?.id)

        XCTAssertTrue(library.renameScene(id: duplicate!.id, layout: .vertical, name: "  Polished Demo  "))
        XCTAssertEqual(library.selectedScene(layout: .vertical)?.name, "Polished Demo")

        XCTAssertTrue(library.moveScene(id: duplicate!.id, layout: .vertical, to: 0))
        XCTAssertEqual(library.scenes(for: .vertical).first?.id, duplicate?.id)

        XCTAssertTrue(library.deleteScene(id: duplicate!.id, layout: .vertical))
        XCTAssertNotEqual(library.selectedScene(layout: .vertical)?.id, duplicate?.id)
        XCTAssertFalse(library.scenes(for: .vertical).contains { $0.id == duplicate?.id })
    }

    func testSceneLibraryKeepsAtLeastOneScenePerLayout() {
        var settings = RecordingSettings()
        settings.layout = .horizontal
        var library = SceneLibrary(
            scenesByLayout: [
                .horizontal: [
                    RecordingSceneDefinition(
                        name: "Only Scene",
                        layout: .horizontal,
                        snapshot: RecordingSceneSnapshot(settings: settings)
                    )
                ]
            ],
            selectedSceneIDsByLayout: [:]
        )
        library.selectedSceneIDsByLayout[.horizontal] = library.scenes(for: .horizontal)[0].id

        XCTAssertFalse(library.deleteScene(id: library.scenes(for: .horizontal)[0].id, layout: .horizontal))
        XCTAssertEqual(library.scenes(for: .horizontal).count, 1)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzrecorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
