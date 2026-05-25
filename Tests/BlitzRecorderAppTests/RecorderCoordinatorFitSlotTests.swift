import CoreGraphics
import Foundation
@testable import BlitzRecorderApp
import XCTest

@MainActor
final class RecorderCoordinatorFitSlotTests: XCTestCase {
    func testSettingCurrentLayoutDoesNotResetCustomSceneFrames() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.3, width: 1, height: 0.7)
        settings.sceneLayout.cameraFrame = CGRect(x: 0.12, y: 0.05, width: 0.76, height: 0.25)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.setLayout(.vertical)

        XCTAssertRect(coordinator.settings.sceneLayout.screenFrame, equals: settings.sceneLayout.screenFrame)
        XCTAssertRect(coordinator.settings.sceneLayout.cameraFrame, equals: settings.sceneLayout.cameraFrame)
        XCTAssertNil(coordinator.settings.selectedScenePreset)
    }

    func testChangingLayoutClearsStaleScreenCrop() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.selectedScenePreset = .screenFocus
        settings.screenCrop = CGRect(x: 0.4, y: 0, width: 0.2, height: 16.0 / 45.0)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.setLayout(.horizontal)

        XCTAssertEqual(coordinator.settings.layout, .horizontal)
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertNil(RecordingSettingsStore.load(defaults: defaults).screenCrop)
    }

    func testLoadingHorizontalLayoutClearsPersistedPortraitScreenCrop() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.screenCrop = CGRect(x: 0.4, y: 0, width: 0.2, height: 16.0 / 45.0)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        XCTAssertEqual(coordinator.settings.layout, .horizontal)
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertNil(RecordingSettingsStore.load(defaults: defaults).screenCrop)
    }

    func testFitScreenToAvailableSlotResizesScreenWithoutMovingCameraOrTargetWindow() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = .stackedHalves
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        settings.sceneLayout.cameraFrame = CGRect(x: 0.12, y: 0.05, width: 0.76, height: 0.25)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var configurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            configurationChangeCount += 1
        }

        let slot = coordinator.fitScreenToAvailableSlot()

        XCTAssertRect(slot, equals: CGRect(x: 0, y: 0.3, width: 1, height: 0.7))
        XCTAssertRect(coordinator.settings.sceneLayout.screenFrame, equals: CGRect(x: 0, y: 0.3, width: 1, height: 0.7))
        XCTAssertRect(coordinator.settings.sceneLayout.cameraFrame, equals: settings.sceneLayout.cameraFrame)
        XCTAssertNil(coordinator.settings.selectedScenePreset)
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertEqual(configurationChangeCount, 1)

        let persisted = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertRect(persisted.sceneLayout.screenFrame, equals: CGRect(x: 0, y: 0.3, width: 1, height: 0.7))
        XCTAssertNil(persisted.screenCrop)
    }

    func testChangingScreenSourceRestartsScreenCaptureConfiguration() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var configurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            configurationChangeCount += 1
        }

        coordinator.addSource(.screen)
        coordinator.setSource(.screen, enabled: false)
        coordinator.removeSource(.screen)

        XCTAssertEqual(configurationChangeCount, 3)
    }

    func testFitSceneLayerFillsCanvasWithSelectedSource() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.selectedScenePreset = .stackedHalves
        settings.screenCrop = CGRect(x: 0, y: 0, width: 1, height: 9.0 / 16.0)
        settings.sceneLayout.screenFrame = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let expectedFrame = SceneLayout.canvasFillingFrame(
            sourceAspectRatio: coordinator.currentScreenSourceAspectRatio(),
            canvasAspectRatio: coordinator.settings.layout.aspectRatio
        )

        coordinator.fitSceneLayer(.screen)

        XCTAssertRect(
            coordinator.settings.sceneLayout.screenFrame,
            equals: expectedFrame
        )
        XCTAssertNil(coordinator.settings.selectedScenePreset)
    }

    func testFitSceneLayerAppliesScaleAroundCanvasCenter() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.fitSceneLayer(.camera, scale: 0.5)

        XCTAssertRect(
            coordinator.settings.sceneLayout.cameraFrame,
            equals: CGRect(x: -0.2901234567901234, y: 0.25, width: 1.5802469135802468, height: 0.5)
        )
    }

    func testEnablingTransparentWebcamCutoutFitsScreenRecordingToCanvas() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = .stackedHalves
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3)
        settings.sceneLayout.screenFrame = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        settings.sceneLayout.cameraFrame = CGRect(x: 0.12, y: 0.05, width: 0.76, height: 0.25)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var configurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            configurationChangeCount += 1
        }

        coordinator.setCameraBackgroundRemovalAfterRecording(true)

        let expectedFrame = SceneLayout.canvasFillingFrame(
            sourceAspectRatio: coordinator.currentScreenSourceAspectRatio(),
            canvasAspectRatio: coordinator.settings.layout.aspectRatio
        )
        XCTAssertTrue(coordinator.settings.removesCameraBackgroundAfterRecording)
        XCTAssertNil(coordinator.settings.selectedScenePreset)
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertRect(coordinator.settings.sceneLayout.screenFrame, equals: expectedFrame)
        XCTAssertRect(coordinator.settings.sceneLayout.cameraFrame, equals: settings.sceneLayout.cameraFrame)
        XCTAssertEqual(configurationChangeCount, 1)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzreels.blitzrecorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private func XCTAssertRect(
    _ actual: CGRect,
    equals expected: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, file: file, line: line)
}
