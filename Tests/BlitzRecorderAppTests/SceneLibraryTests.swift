import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class SceneLibraryDefaultLayoutTests: XCTestCase {
    func testWideCanvasesStartOnCameraLeftWithFixedLayouts() throws {
        let library = SceneLibrary.defaultLibrary()
        for canvas in [CaptureLayout.horizontal, .square] {
            let scenes = library.scenes(for: canvas)
            XCTAssertEqual(scenes.map(\.name), ["Screen + Camera", "Camera Inset", "Screen", "Camera"])
            let first = try XCTUnwrap(scenes.first)
            XCTAssertEqual(first.snapshot.selectedScenePreset, .webcamLeft)
            XCTAssertEqual(library.selectedScene(layout: canvas)?.id, first.id)
            let width = SceneLayout.defaultSideBySideCameraWidth(for: canvas)
            XCTAssertEqual(first.snapshot.sceneLayout.cameraFrame, CGRect(x: 0, y: 0, width: width, height: 1))
            XCTAssertEqual(first.snapshot.sceneLayout.screenFrame, CGRect(x: width, y: 0, width: 1 - width, height: 1))
        }
        XCTAssertEqual(
            library.scenes(for: .vertical).map(\.name),
            ["Screen + Camera", "Camera Inset", "Screen", "Camera"]
        )
    }

    func testWideCameraColumnIsPortraitNineBySixteen() {
        XCTAssertEqual(SceneLayout.defaultSideBySideCameraWidth(for: .horizontal), 81.0 / 256.0, accuracy: 0.0001)
        XCTAssertEqual(SceneLayout.defaultSideBySideCameraWidth(for: .square), 0.4, accuracy: 0.0001)
    }

    func testSideBySideWidthIsClampedAndKeepsCameraSide() {
        let right = SceneLayout.sideBySideLayout(.init(cameraWidth: 0.9, cameraSide: .right))
        XCTAssertEqual(right.cameraSide, .right)
        XCTAssertEqual(right.sideBySideCameraWidth ?? 0, SceneLayout.maximumSideBySideCameraWidth, accuracy: 0.0001)
        XCTAssertEqual(right.screenFrame.minX, 0, accuracy: 0.0001)
    }

    func testLegacyDefaultCameraWidthMigratesToPortraitWidth() {
        var library = SceneLibrary.defaultLibrary()
        library.scenesByLayout[.horizontal]?[0].snapshot.sceneLayout = SceneLayout.sideBySideLayout(
            .init(cameraWidth: 0.4, cameraSide: .right)
        )
        library.canonicalize()
        let migrated = library.scenes(for: .horizontal)[0].snapshot.sceneLayout
        XCTAssertEqual(migrated.cameraSide, .right)
        XCTAssertEqual(migrated.sideBySideCameraWidth ?? 0, 81.0 / 256.0, accuracy: 0.0001)
    }

    func testEachFixedLayoutShowsOnlyItsSources() {
        let scenes = SceneLibrary.defaultLibrary().scenes(for: .horizontal)
        XCTAssertEqual(scenes[2].snapshot.hiddenVideoSources, [.camera])
        XCTAssertEqual(scenes[3].snapshot.hiddenVideoSources, [.screen])
        for scene in scenes.prefix(2) {
            XCTAssertTrue(scene.snapshot.hiddenVideoSources.isEmpty)
        }
    }

    func testCanonicalizeRepairsDriftedScenesAndKeepsLayoutTweaks() throws {
        var library = SceneLibrary.defaultLibrary()
        var scenes = library.scenes(for: .horizontal)
        scenes[3].name = "Camera Only"
        scenes[3].snapshot.selectedScenePreset = .webcamLeft
        scenes[3].snapshot.hiddenVideoSources = []
        scenes[1].snapshot.sceneLayout.cameraFrame.size.width = 0.45
        scenes[0].snapshot.hiddenVideoSources = [.camera]
        let custom = RecordingSceneDefinition(name: "My demo", layout: .horizontal, snapshot: scenes[2].snapshot)
        library.scenesByLayout[.horizontal] = scenes + [custom]
        library.selectedSceneIDsByLayout[.horizontal] = scenes[3].id

        XCTAssertTrue(library.canonicalize())
        let repaired = library.scenes(for: .horizontal)
        XCTAssertEqual(repaired.map(\.name), ["Screen + Camera", "Camera Inset", "Screen", "Camera"])
        XCTAssertEqual(repaired[0].id, scenes[3].id)
        XCTAssertEqual(repaired[1].snapshot.sceneLayout.cameraFrame.width, 0.45, accuracy: 0.0001)
        XCTAssertTrue(repaired[0].snapshot.hiddenVideoSources.isEmpty)
        XCTAssertEqual(repaired[3].snapshot.selectedScenePreset, .webcamFullscreen)
        XCTAssertEqual(repaired[3].snapshot.hiddenVideoSources, [.screen])
        XCTAssertEqual(library.selectedScene(layout: .horizontal)?.id, repaired[0].id)
        XCTAssertFalse(library.canonicalize())
    }

    func testStoreRepairsAndPersistsLegacyLibraries() throws {
        let suite = "SceneLibraryDefaultLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = SceneLibrary.defaultLibrary()
        legacy.scenesByLayout[.vertical]?[0].name = "Screen + Cam"
        let duplicate = legacy.scenes(for: .vertical)[0]
        legacy.scenesByLayout[.vertical]?.append(duplicate)
        SceneLibraryStore.save(legacy, defaults: defaults)

        let loaded = SceneLibraryStore.load(defaults: defaults, currentSettings: RecordingSettings())
        XCTAssertEqual(loaded.scenes(for: .vertical).map(\.name), ["Screen + Camera", "Camera Inset", "Screen", "Camera"])
        XCTAssertEqual(SceneLibraryStore.load(defaults: defaults, currentSettings: RecordingSettings()), loaded)
    }
}

@MainActor
final class SceneLibraryTests: XCTestCase {
    func testDefaultLibrarySelectsTheSceneMatchingCurrentPreset() {
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.selectedScenePreset = .cameraRight

        let library = SceneLibrary.defaultLibrary(currentSettings: settings)

        XCTAssertEqual(library.selectedScene(layout: .horizontal)?.name, "Screen + Camera")
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

    func testSceneSnapshotPersistsScreenContentMode() throws {
        var settings = RecordingSettings()
        settings.screenContentMode = .fit

        let snapshot = RecordingSceneSnapshot(settings: settings)
        let decoded = try JSONDecoder().decode(
            RecordingSceneSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.screenContentMode, .fit)
    }

    func testSceneSnapshotDefaultsMissingScreenContentModeToFill() throws {
        let snapshot = RecordingSceneSnapshot(settings: RecordingSettings())
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        payload.removeValue(forKey: "screenContentMode")

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(RecordingSceneSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.screenContentMode, .fill)
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

    func testSceneSnapshotDecodesLegacyLayoutWithoutCameraMaskAsRectangle() throws {
        var settings = RecordingSettings()
        settings.sceneLayout.cameraMask = .circle
        let snapshot = RecordingSceneSnapshot(settings: settings)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var layout = try XCTUnwrap(payload["sceneLayout"] as? [String: Any])
        XCTAssertEqual(layout["cameraMask"] as? String, "circle")
        layout.removeValue(forKey: "cameraMask")
        payload["sceneLayout"] = layout

        let legacyData = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(RecordingSceneSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.sceneLayout.cameraMask, .rectangle)
        XCTAssertEqual(decoded.sceneLayout.cameraFrame, settings.sceneLayout.cameraFrame)
    }

    func testSceneSnapshotRoundTripsCircleCameraMask() throws {
        var settings = RecordingSettings()
        settings.sceneLayout.cameraMask = .circle

        let decoded = try JSONDecoder().decode(
            RecordingSceneSnapshot.self,
            from: JSONEncoder().encode(RecordingSceneSnapshot(settings: settings))
        )

        XCTAssertEqual(decoded.applying(to: RecordingSettings()).sceneLayout.cameraMask, .circle)
    }

    func testProjectSceneSnapshotDecodesLegacyLayoutAndRoundTripsCircle() throws {
        var layout = SceneLayout.cameraInsetLayout(for: .horizontal, shape: .circle)
        layout.cameraMask = .circle
        let scene = RecordingScene(enabledSources: [.screen, .camera], sceneLayout: layout)
        let encoded = try JSONEncoder().encode(RecordingProject.SceneSnapshot(scene))

        let roundTripped = try JSONDecoder().decode(RecordingProject.SceneSnapshot.self, from: encoded)
        XCTAssertEqual(RecordingScene(snapshot: roundTripped)?.sceneLayout.cameraMask, .circle)
        XCTAssertEqual(RecordingScene(snapshot: roundTripped)?.sceneLayout, layout)

        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var layoutPayload = try XCTUnwrap(payload["sceneLayout"] as? [String: Any])
        layoutPayload.removeValue(forKey: "cameraMask")
        payload["sceneLayout"] = layoutPayload
        let legacy = try JSONDecoder().decode(
            RecordingProject.SceneSnapshot.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        let legacyScene = try XCTUnwrap(RecordingScene(snapshot: legacy))
        XCTAssertEqual(legacyScene.sceneLayout.cameraMask, .rectangle)
        XCTAssertEqual(legacyScene.sceneLayout.cameraFrame, layout.cameraFrame)
    }

    func testPortableSceneLayoutDecodesMissingCameraShapeAsRectangle() throws {
        let legacy = Data("""
        {"canvasWidth":1920,"canvasHeight":1080,"screen":{"x":0,"y":0,"width":1,"height":1},\
        "camera":{"x":0.68,"y":0.68,"width":0.28,"height":0.28}}
        """.utf8)
        let decoded = try JSONDecoder().decode(PortableSceneLayout.self, from: legacy)
        XCTAssertEqual(decoded.cameraShape, .rectangle)
        XCTAssertEqual(decoded.camera, .cameraPip)

        var circle = decoded
        circle.cameraShape = .circle
        let roundTripped = try JSONDecoder().decode(PortableSceneLayout.self, from: JSONEncoder().encode(circle))
        XCTAssertEqual(roundTripped.cameraShape, .circle)
    }

    func testSettingsStorePersistsCircleCameraMask() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings = RecordingSceneMutation.applyingCameraInset(
            alignment: .bottomLeft,
            shape: .circle,
            size: 0.3,
            to: settings,
            screenAspectRatio: 16.0 / 9.0,
            cameraAspectRatio: 16.0 / 9.0
        ).settings

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.sceneLayout.cameraMask, .circle)
        XCTAssertEqual(loaded.sceneLayout.cameraInsetShape(in: .horizontal), .circle)
    }

    func testCameraOnlyAndDefaultScreenScenePreserveChosenWindow() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults), defaults: defaults
        )
        let window = ScreenSourceBinding(
            kind: .window, displayID: nil, bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome", processID: nil, windowID: 123, windowTitle: "Recording test"
        )
        coordinator.setScreenSource(window)
        let scenes = coordinator.sceneLibrary.scenes(for: .vertical)
        coordinator.selectScene(id: scenes[2].id)
        XCTAssertEqual(coordinator.settings.screenSourceBinding, window)
        coordinator.selectScene(id: scenes[0].id)
        XCTAssertEqual(coordinator.settings.screenSourceBinding, window)
        coordinator.selectScene(id: scenes[1].id)
        XCTAssertEqual(coordinator.settings.screenSourceBinding, window)
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

    func testSceneSwitchChangesLayoutButKeepsCameraDeviceAndBackground() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.selectedCameraID = "current-camera"
        settings.canvasBackgroundStyle = .graphite
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let scenes = coordinator.sceneLibrary.scenes(for: .horizontal)

        coordinator.selectScene(id: scenes[3].id)
        XCTAssertEqual(coordinator.settings.selectedScenePreset, .webcamFullscreen)
        XCTAssertTrue(coordinator.settings.hiddenSources.contains(.screen))
        XCTAssertEqual(coordinator.settings.selectedCameraID, "current-camera")
        XCTAssertEqual(coordinator.settings.canvasBackgroundStyle, .graphite)

        coordinator.selectScene(id: scenes[0].id)
        XCTAssertEqual(coordinator.settings.selectedScenePreset, .webcamLeft)
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.screen))
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.camera))
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzrecorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testUnknownCameraMaskDecodesAsRectangle() throws {
        let mask = try JSONDecoder().decode([SceneCameraMask].self, from: Data(#"["hexagon","circle"]"#.utf8))
        XCTAssertEqual(mask, [.rectangle, .circle])
    }
}
