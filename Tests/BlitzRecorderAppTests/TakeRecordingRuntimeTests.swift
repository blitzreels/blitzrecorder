@testable import BlitzRecorderApp
import XCTest

@MainActor
final class TakeRecordingRuntimeTests: XCTestCase {
    func testLocalCaptureSettingsRemovesRemoteCameraOnlyFromCaptureRun() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone]
        let runtime = TakeRecordingRuntime()

        let local = runtime.localCaptureSettings(settings, usesRemoteCamera: true)

        XCTAssertEqual(local.enabledSources, [.screen, .microphone])
        XCTAssertEqual(settings.enabledSources, [.screen, .camera, .microphone])
    }

    func testLiveCompositorRuleRequiresDirectLocalRecording() {
        var settings = RecordingSettings()
        settings.savesSourceFiles = false
        settings.removesCameraBackgroundAfterRecording = false

        XCTAssertTrue(TakeRecordingRuntime.shouldUseLiveCompositor(settings: settings, isRemoteCameraSelected: false))
        XCTAssertFalse(TakeRecordingRuntime.shouldUseLiveCompositor(settings: settings, isRemoteCameraSelected: true))

        settings.savesSourceFiles = true
        XCTAssertFalse(TakeRecordingRuntime.shouldUseLiveCompositor(settings: settings, isRemoteCameraSelected: false))
    }

    func testTakeStartPlanSelectsRemoteCameraCapturePath() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.savesSourceFiles = false

        let plan = TakeStartPlan.make(settings: settings, isRemoteCameraSelected: true)

        XCTAssertTrue(plan.usesRemoteCamera)
        XCTAssertFalse(plan.usesLiveCompositor)
        XCTAssertEqual(plan.localCaptureSettings.enabledSources, [.screen, .microphone])
    }

    func testTakeStartPlanKeepsLocalCameraInLiveCompositorPath() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera]
        settings.savesSourceFiles = false
        settings.removesCameraBackgroundAfterRecording = false

        let plan = TakeStartPlan.make(settings: settings, isRemoteCameraSelected: false)

        XCTAssertFalse(plan.usesRemoteCamera)
        XCTAssertTrue(plan.usesLiveCompositor)
        XCTAssertEqual(plan.localCaptureSettings.enabledSources, [.screen, .camera])
    }

    func testSceneTimelineStoresRequestedTransition() {
        var settings = RecordingSettings()
        settings.canvasBackgroundStyle = .black
        let runtime = TakeRecordingRuntime()
        runtime.startSceneTimeline(settings: settings)

        settings.canvasBackgroundStyle = .aurora
        runtime.appendSceneEventIfNeeded(
            RecordingScene(settings: settings),
            state: .recording,
            transition: .sceneSwitch
        )

        XCTAssertEqual(runtime.sceneEvents.last?.transition, .sceneSwitch)
    }
}
