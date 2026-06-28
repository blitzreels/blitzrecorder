import CoreGraphics
import Foundation
import BlitzRecorderCore
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

    func testChangingLayoutPreservesSelectedAppScreenSourceAndAdaptsPresetToSourceAspectRatio() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        let appBinding = ScreenSourceBinding(
            kind: .application,
            displayID: "1",
            bundleIdentifier: "com.bitwarden.desktop",
            applicationName: "Bitwarden",
            processID: 123,
            windowID: nil,
            windowTitle: nil
        )
        coordinator.setScreenSource(appBinding)
        coordinator.noteScreenSourceAspectRatio(1.25)

        coordinator.setLayout(.horizontal)

        let expectedLayout = SceneLayout.presetLayout(
            .cameraInset,
            for: .horizontal,
            screenAspectRatio: 1.25,
            cameraAspectRatio: coordinator.currentCameraSourceAspectRatio()
        )
        XCTAssertEqual(coordinator.settings.layout, .horizontal)
        XCTAssertEqual(coordinator.settings.screenSourceBinding, appBinding)
        XCTAssertEqual(coordinator.settings.selectedScenePreset, .cameraInset)
        XCTAssertRect(coordinator.settings.sceneLayout.screenFrame, equals: expectedLayout.screenFrame)
        XCTAssertRect(coordinator.settings.sceneLayout.cameraFrame, equals: expectedLayout.cameraFrame)
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

    func testChangingScreenSplitHeightClearsStaleScreenCropAndRestartsScreenCapture() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = .screenTop50
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        settings.sceneLayout = SceneLayout.screenSplitLayout(screenHeight: 0.5)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var configurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            configurationChangeCount += 1
        }

        coordinator.setScreenSplitHeight(0.64)

        XCTAssertEqual(coordinator.settings.selectedScenePreset, .screenTop50)
        XCTAssertRect(
            coordinator.settings.sceneLayout.screenFrame,
            equals: CGRect(x: 0, y: 0.36, width: 1, height: 0.64)
        )
        XCTAssertRect(
            coordinator.settings.sceneLayout.cameraFrame,
            equals: CGRect(x: 0, y: 0, width: 1, height: 0.36)
        )
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertEqual(configurationChangeCount, 1)
        XCTAssertNil(RecordingSettingsStore.load(defaults: defaults).screenCrop)
    }

    func testDraggingScreenFrameClearsStaleScreenCropAndRestartsScreenCapture() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = .screenTop50
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        settings.sceneLayout = SceneLayout.screenSplitLayout(screenHeight: 0.5)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var configurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            configurationChangeCount += 1
        }

        var layout = coordinator.settings.sceneLayout
        layout.screenFrame = CGRect(x: 0, y: 0.42, width: 1, height: 0.58)
        coordinator.setSceneLayout(layout)

        XCTAssertNil(coordinator.settings.selectedScenePreset)
        XCTAssertRect(
            coordinator.settings.sceneLayout.screenFrame,
            equals: CGRect(x: 0, y: 0.42, width: 1, height: 0.58)
        )
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertEqual(configurationChangeCount, 1)
        XCTAssertNil(RecordingSettingsStore.load(defaults: defaults).screenCrop)
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
        settings.enabledSources = [.screen]
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

    func testFitScreenLayerInLeftCamLayoutStaysBesideCamera() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = .webcamLeft
        settings.sceneLayout = SceneLayout.presetLayout(.webcamLeft, for: .horizontal)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.fitSceneLayer(.screen)

        XCTAssertRect(
            coordinator.settings.sceneLayout.screenFrame,
            equals: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
        )
        XCTAssertEqual(
            coordinator.settings.sceneLayout.screenFrame.minX,
            coordinator.settings.sceneLayout.cameraFrame.maxX,
            accuracy: 0.0001
        )
        XCTAssertNil(coordinator.settings.selectedScenePreset)
    }

    func testFitSceneLayerAppliesScaleAroundCanvasCenter() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.sceneLayout.cameraFrame = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        settings.selectedCameraID = RemoteCameraProviderID.make(for: "iphone-15-pro")
        RecordingSettingsStore.save(settings, defaults: defaults)
        defaults.set("BRL1_saved", forKey: "access.blitzRecorderLicenseKey")

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

    func testWebcamFullscreenPresetHidesScreenSourceAndEnablesCamera() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .microphone]
        settings.hiddenSources = [.camera]
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var screenConfigurationChangeCount = 0
        var cameraConfigurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            screenConfigurationChangeCount += 1
        }
        coordinator.onCameraConfigurationChanged = {
            cameraConfigurationChangeCount += 1
        }

        coordinator.applyScenePreset(.webcamFullscreen)

        XCTAssertTrue(coordinator.settings.enabledSources.contains(.camera))
        XCTAssertTrue(coordinator.settings.enabledSources.contains(.screen))
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.camera))
        XCTAssertTrue(coordinator.settings.hiddenSources.contains(.screen))
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertEqual(screenConfigurationChangeCount, 1)
        XCTAssertEqual(cameraConfigurationChangeCount, 1)

        let persisted = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertTrue(persisted.enabledSources.contains(.camera))
        XCTAssertTrue(persisted.enabledSources.contains(.screen))
        XCTAssertTrue(persisted.hiddenSources.contains(.screen))
    }

    func testScreenFullscreenPresetHidesCameraSourceAndEnablesScreen() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.camera, .microphone]
        settings.hiddenSources = [.screen]
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3)
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var screenConfigurationChangeCount = 0
        var cameraConfigurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            screenConfigurationChangeCount += 1
        }
        coordinator.onCameraConfigurationChanged = {
            cameraConfigurationChangeCount += 1
        }

        coordinator.applyScenePreset(.screenFullscreen)

        XCTAssertTrue(coordinator.settings.enabledSources.contains(.screen))
        XCTAssertTrue(coordinator.settings.enabledSources.contains(.camera))
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.screen))
        XCTAssertTrue(coordinator.settings.hiddenSources.contains(.camera))
        XCTAssertNil(coordinator.settings.screenCrop)
        XCTAssertEqual(screenConfigurationChangeCount, 1)
        XCTAssertEqual(cameraConfigurationChangeCount, 1)

        let persisted = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertTrue(persisted.enabledSources.contains(.screen))
        XCTAssertTrue(persisted.enabledSources.contains(.camera))
        XCTAssertTrue(persisted.hiddenSources.contains(.camera))
    }

    func testMixedScenePresetEnablesBothVideoSources() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .microphone]
        settings.hiddenSources = [.camera]
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var cameraConfigurationChangeCount = 0
        coordinator.onCameraConfigurationChanged = {
            cameraConfigurationChangeCount += 1
        }

        coordinator.applyScenePreset(.stackedHalves)

        XCTAssertTrue(coordinator.settings.enabledSources.contains(.screen))
        XCTAssertTrue(coordinator.settings.enabledSources.contains(.camera))
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.screen))
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.camera))
        XCTAssertEqual(cameraConfigurationChangeCount, 1)

        let persisted = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertTrue(persisted.enabledSources.contains(.screen))
        XCTAssertTrue(persisted.enabledSources.contains(.camera))
        XCTAssertFalse(persisted.hiddenSources.contains(.camera))
    }

    func testCameraInsetRestartsPreviewsWhenHiddenSourcesBecomeVisible() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.screen, .camera]
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )
        var screenConfigurationChangeCount = 0
        var cameraConfigurationChangeCount = 0
        coordinator.onScreenCaptureConfigurationChanged = {
            screenConfigurationChangeCount += 1
        }
        coordinator.onCameraConfigurationChanged = {
            cameraConfigurationChangeCount += 1
        }

        coordinator.setCameraInset(alignment: .bottomRight, shape: .portrait, size: 0.28)

        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.screen))
        XCTAssertFalse(coordinator.settings.hiddenSources.contains(.camera))
        XCTAssertEqual(screenConfigurationChangeCount, 1)
        XCTAssertEqual(cameraConfigurationChangeCount, 1)
    }

    func testScenePresetsNormalizeVideoSourcesForEverySupportedLayout() {
        for layout in CaptureLayout.allCases {
            for preset in ScenePreset.allCases where preset.supports(layout) {
                assertScenePresetSourceState(
                    preset: preset,
                    layout: layout,
                    initialEnabledSources: [.screen, .microphone],
                    initialHiddenSources: [.camera]
                )
                assertScenePresetSourceState(
                    preset: preset,
                    layout: layout,
                    initialEnabledSources: [.camera, .microphone],
                    initialHiddenSources: [.screen]
                )
            }
        }
    }

    func testEnablingTransparentWebcamCutoutFitsScreenRecordingToCanvas() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.screen, .camera]
        settings.selectedScenePreset = .stackedHalves
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.3)
        settings.cameraCropAmount = CGPoint(x: 0.35, y: 0.2)
        settings.cameraCropPosition = CGPoint(x: -0.4, y: 0.6)
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
        XCTAssertEqual(coordinator.settings.cameraCropAmount, .zero)
        XCTAssertEqual(coordinator.settings.cameraCropPosition, .zero)
        XCTAssertRect(coordinator.settings.sceneLayout.screenFrame, equals: expectedFrame)
        XCTAssertRect(coordinator.settings.sceneLayout.cameraFrame, equals: settings.sceneLayout.cameraFrame)
        XCTAssertEqual(configurationChangeCount, 1)
    }

    private func assertScenePresetSourceState(
        preset: ScenePreset,
        layout: CaptureLayout,
        initialEnabledSources: Set<CaptureSource>,
        initialHiddenSources: Set<CaptureSource>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.layout = layout
        settings.enabledSources = initialEnabledSources
        settings.hiddenSources = initialHiddenSources
        RecordingSettingsStore.save(settings, defaults: defaults)

        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults),
            defaults: defaults
        )

        coordinator.applyScenePreset(preset)

        switch preset {
        case .webcamFullscreen:
            XCTAssertTrue(coordinator.settings.enabledSources.contains(.screen), file: file, line: line)
            XCTAssertTrue(coordinator.settings.enabledSources.contains(.camera), file: file, line: line)
            XCTAssertTrue(coordinator.settings.hiddenSources.contains(.screen), file: file, line: line)
            XCTAssertFalse(coordinator.settings.hiddenSources.contains(.camera), file: file, line: line)
        case .screenFullscreen:
            XCTAssertTrue(coordinator.settings.enabledSources.contains(.screen), file: file, line: line)
            XCTAssertTrue(coordinator.settings.enabledSources.contains(.camera), file: file, line: line)
            XCTAssertFalse(coordinator.settings.hiddenSources.contains(.screen), file: file, line: line)
            XCTAssertTrue(coordinator.settings.hiddenSources.contains(.camera), file: file, line: line)
        case .stackedHalves, .screenTop50, .screenTop70, .screenFocus, .cameraInset, .cameraFocus, .webcamLeft:
            XCTAssertTrue(coordinator.settings.enabledSources.contains(.screen), file: file, line: line)
            XCTAssertTrue(coordinator.settings.enabledSources.contains(.camera), file: file, line: line)
            XCTAssertFalse(coordinator.settings.hiddenSources.contains(.screen), file: file, line: line)
            XCTAssertFalse(coordinator.settings.hiddenSources.contains(.camera), file: file, line: line)
        }
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
