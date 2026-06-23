import CoreGraphics
import BlitzRecorderCore
@testable import BlitzRecorderApp
import XCTest

final class RecordingSettingsStoreTests: XCTestCase {
    func testSocialExportBitratesStayLightweight() {
        var settings = RecordingSettings()

        settings.outputResolution = .p1080
        settings.framesPerSecond = 30
        XCTAssertEqual(settings.finalVideoBitrate, 8_000_000)

        settings.framesPerSecond = 60
        XCTAssertEqual(settings.finalVideoBitrate, 12_000_000)

        settings.outputResolution = .p2160
        XCTAssertEqual(settings.finalVideoBitrate, 35_000_000)
        XCTAssertLessThan(settings.finalVideoBitrate, settings.screenBitrate + settings.cameraBitrate)
    }

    func testLoadKeepsCustomSceneFramesWhenPresetKeyIsStale() {
        let defaults = temporaryDefaults()
        defaults.set(CaptureLayout.vertical.rawValue, forKey: "recording.layout")
        defaults.set(ScenePreset.stackedHalves.rawValue, forKey: "scene.selectedScenePreset")
        defaults.set("0.18,0.43,0.64,0.57", forKey: "scene.screenFrame")
        defaults.set("0.0,0.0,1.0,0.5", forKey: "scene.cameraFrame")

        let settings = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertNil(settings.selectedScenePreset)
        XCTAssertRect(
            settings.sceneLayout.screenFrame,
            equals: CGRect(x: 0.18, y: 0.43, width: 0.64, height: 0.57)
        )
    }

    func testLoadKeepsPresetWhenSavedFramesMatchPreset() {
        let defaults = temporaryDefaults()
        let presetLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        defaults.set(CaptureLayout.vertical.rawValue, forKey: "recording.layout")
        defaults.set(ScenePreset.stackedHalves.rawValue, forKey: "scene.selectedScenePreset")
        defaults.set(rectString(presetLayout.screenFrame), forKey: "scene.screenFrame")
        defaults.set(rectString(presetLayout.cameraFrame), forKey: "scene.cameraFrame")

        let settings = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.selectedScenePreset, .stackedHalves)
        XCTAssertRect(settings.sceneLayout.screenFrame, equals: presetLayout.screenFrame)
    }

    func testLoadKeepsAdjustedScreenSplitPreset() {
        let defaults = temporaryDefaults()
        let splitLayout = SceneLayout.screenSplitLayout(screenHeight: 0.62)
        defaults.set(CaptureLayout.vertical.rawValue, forKey: "recording.layout")
        defaults.set(ScenePreset.screenTop50.rawValue, forKey: "scene.selectedScenePreset")
        defaults.set(rectString(splitLayout.screenFrame), forKey: "scene.screenFrame")
        defaults.set(rectString(splitLayout.cameraFrame), forKey: "scene.cameraFrame")

        let settings = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.selectedScenePreset, .screenTop50)
        XCTAssertRect(settings.sceneLayout.screenFrame, equals: splitLayout.screenFrame)
        XCTAssertRect(settings.sceneLayout.cameraFrame, equals: splitLayout.cameraFrame)
    }

    func testLoadDropsRemovedCameraFocusPreset() {
        let defaults = temporaryDefaults()
        let focusLayout = SceneLayout.presetLayout(.cameraFocus, for: .horizontal)
        defaults.set(CaptureLayout.horizontal.rawValue, forKey: "recording.layout")
        defaults.set(ScenePreset.cameraFocus.rawValue, forKey: "scene.selectedScenePreset")
        defaults.set(rectString(focusLayout.screenFrame), forKey: "scene.screenFrame")
        defaults.set(rectString(focusLayout.cameraFrame), forKey: "scene.cameraFrame")

        let settings = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertNil(settings.selectedScenePreset)
        XCTAssertRect(
            settings.sceneLayout.screenFrame,
            equals: SceneLayout.defaultLayout(for: .horizontal).screenFrame
        )
        XCTAssertRect(
            settings.sceneLayout.cameraFrame,
            equals: SceneLayout.defaultLayout(for: .horizontal).cameraFrame
        )
    }

    func testLoadKeepsLegacyStackedPresetAsEqualHalves() {
        let defaults = temporaryDefaults()
        let presetLayout = SceneLayout.presetLayout(.stackedHalves, for: .vertical)
        defaults.set(CaptureLayout.vertical.rawValue, forKey: "recording.layout")
        defaults.set(ScenePreset.stackedHalves.rawValue, forKey: "scene.selectedScenePreset")
        defaults.set("0.0,0.5,1.0,0.5", forKey: "scene.screenFrame")
        defaults.set("0.0,0.0,1.0,0.5", forKey: "scene.cameraFrame")

        let settings = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.selectedScenePreset, .stackedHalves)
        XCTAssertRect(settings.sceneLayout.screenFrame, equals: presetLayout.screenFrame)
        XCTAssertRect(settings.sceneLayout.cameraFrame, equals: presetLayout.cameraFrame)
    }

    func testPersistsTrustedRemoteCameraServiceIDs() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.trustedRemoteCameraServiceIDs = [
            "Alice-iPhone._blitzrecorder-camera._tcp.local."
        ]

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.trustedRemoteCameraServiceIDs, settings.trustedRemoteCameraServiceIDs)
    }

    func testPersistsRemoteCameraSettingsByServiceID() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.remoteCameraSettingsByServiceID = [
            "Alice-iPhone._blitzrecorder-camera._tcp.local.": RemoteCameraSettings(
                lens: .telephoto,
                formatID: "3840x2160",
                frameRate: 30,
                captureProfileID: .highEfficiency,
                zoomFactor: 2.4,
                stabilizationMode: .cinematic,
                rotationDegrees: 90
            )
        ]

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.remoteCameraSettingsByServiceID, settings.remoteCameraSettingsByServiceID)
    }

    func testPersistsScreenSourceBinding() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.screenSourceBinding = ScreenSourceBinding(
            kind: .application,
            displayID: "1",
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            processID: 42,
            windowID: nil,
            windowTitle: nil
        )

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.screenSourceBinding, settings.screenSourceBinding)
        XCTAssertFalse(loaded.usesPickedScreenContent)
    }

    func testSaveSourceFilesDefaultsOnAndIgnoresLegacyOptOut() {
        let defaults = temporaryDefaults()

        XCTAssertTrue(RecordingSettingsStore.load(defaults: defaults).savesSourceFiles)
        XCTAssertFalse(RecordingSettingsStore.load(defaults: defaults).renamesRecordingsFromSpeech)

        var settings = RecordingSettings()
        settings.savesSourceFiles = false
        settings.renamesRecordingsFromSpeech = true
        RecordingSettingsStore.save(settings, defaults: defaults)

        XCTAssertTrue(RecordingSettingsStore.load(defaults: defaults).savesSourceFiles)
        XCTAssertTrue(RecordingSettingsStore.load(defaults: defaults).renamesRecordingsFromSpeech)
    }

    func testPersistsCameraCropAmount() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.cameraCropAmount = CGPoint(x: 0.35, y: 0.6)
        settings.cameraCropPosition = CGPoint(x: -0.4, y: 0.7)

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.cameraCropAmount, settings.cameraCropAmount)
        XCTAssertEqual(loaded.cameraCropPosition, settings.cameraCropPosition)
    }

    func testPersistsCameraFrameOptionsWithoutLegacyFramePadding() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.cameraContentMode = .fit
        settings.cameraFramePadding = 0.12
        settings.cameraShadowEnabled = true

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.cameraContentMode, .fit)
        XCTAssertEqual(loaded.cameraFramePadding, 0, accuracy: 0.0001)
        XCTAssertTrue(loaded.cameraShadowEnabled)
    }

    func testPersistsCanvasAppearance() {
        let defaults = temporaryDefaults()
        var settings = RecordingSettings()
        settings.canvasBackgroundStyle = .aurora
        settings.canvasPadding = 0.08

        RecordingSettingsStore.save(settings, defaults: defaults)
        let loaded = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(loaded.canvasBackgroundStyle, .aurora)
        XCTAssertEqual(loaded.canvasPadding, 0.08, accuracy: 0.0001)
    }

    func testClampsCanvasPaddingOnLoad() {
        let defaults = temporaryDefaults()
        defaults.set(0.5, forKey: "scene.canvasPadding")

        let settings = RecordingSettingsStore.load(defaults: defaults)

        XCTAssertEqual(settings.canvasPadding, 0.16, accuracy: 0.0001)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "dev.blitzreels.blitzrecorder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
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

private func rectString(_ rect: CGRect) -> String {
    "\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height)"
}
