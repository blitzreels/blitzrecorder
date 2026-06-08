@testable import BlitzRecorderApp
import CoreMedia
import Foundation
import ScreenCaptureKit
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

    func testLiveCompositorStopPreservesCompletedOutputWhenStreamReportsError() async throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .systemAudio]
        let take = makeTake()
        let recorder = StopFailureLiveCompositedRecorder(
            completion: .wrote(take.finalVideoURL),
            error: RecorderError.captureStreamStopped("display went away")
        )
        let runtime = TakeRecordingRuntime(liveCompositedRecorder: recorder)

        try await runtime.startLiveCompositedTake(
            take: take,
            settings: settings,
            pickedScreenFilter: nil,
            prerollSeconds: 0,
            prerollHandler: nil
        )
        let outcome = try await runtime.stop()

        guard case .liveComposited(let completion, let warning) = outcome else {
            return XCTFail("Expected live composited completion")
        }
        XCTAssertEqual(completion, .wrote(take.finalVideoURL))
        XCTAssertTrue(warning?.contains("display went away") == true)
    }

    func testTakeStartPlanSelectsRemoteCameraCapturePath() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.savesSourceFiles = false

        let plan = TakeStartPlan.make(settings: settings, isRemoteCameraSelected: true)

        XCTAssertTrue(plan.usesRemoteCamera)
        XCTAssertFalse(plan.usesLiveCompositor)
        XCTAssertEqual(plan.localCaptureSettings.enabledSources, [.screen, .microphone])
        XCTAssertEqual(plan.sceneTimelineSettings.enabledSources, [.screen, .camera, .microphone])
    }

    func testRemoteCameraSourceFileTakeKeepsCameraInRenderTimeline() async throws {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .camera, .microphone]
        let plan = TakeStartPlan.make(settings: settings, isRemoteCameraSelected: true)
        let runtime = TakeRecordingRuntime()
        let take = makeTake()
        let remoteCamera = NoopRemoteCameraCaptureRecorder(completion: .wrote(take.cameraURL))

        _ = try await runtime.startSourceFileTake(
            take: take,
            settings: plan.localCaptureSettings,
            sceneTimelineSettings: plan.sceneTimelineSettings,
            pickedScreenFilter: nil,
            prerollSeconds: 0,
            screenRecorder: NoopScreenCaptureRecorder(),
            cameraRecorder: NoopCameraCaptureRecorder(),
            remoteCameraRecorder: remoteCamera,
            audioRecorder: NoopMicrophoneCaptureRecorder(),
            systemAudioRecorder: NoopSystemAudioCaptureRecorder(),
            prerollHandler: nil
        )

        XCTAssertEqual(runtime.sceneEvents.first?.scene.enabledSources, [.screen, .camera, .microphone])
        XCTAssertFalse(plan.localCaptureSettings.enabledSources.contains(.camera))
        let outcome = try await runtime.stop()
        guard case .sourceFiles(let summary) = outcome else {
            return XCTFail("Expected source file summary")
        }
        XCTAssertEqual(remoteCamera.startCount, 1)
        XCTAssertEqual(summary.completions[.camera], .wrote(take.cameraURL))
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
        XCTAssertEqual(plan.sceneTimelineSettings.enabledSources, [.screen, .camera])
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

    private func makeTake() -> RecordingTake {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return RecordingTake(
            scratchDirectory: root,
            screenURL: root.appendingPathComponent("screen.mov"),
            cameraURL: root.appendingPathComponent("camera.mov"),
            audioURL: root.appendingPathComponent("audio.m4a"),
            systemAudioURL: root.appendingPathComponent("system-audio.m4a"),
            transcriptURL: root.appendingPathComponent("transcript.txt"),
            finalVideoURL: root.appendingPathComponent("final.mov"),
            outputVideoFormat: .mov,
            titleSlug: nil
        )
    }
}

private final class NoopScreenCaptureRecorder: ScreenCaptureRecording {
    func start(url: URL, settings: RecordingSettings, filter pickedFilter: SCContentFilter?, timelineStartTime: CMTime?) async throws {}
    func update(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .wrote() }
}

private final class NoopCameraCaptureRecorder: CameraCaptureRecording {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .wrote() }
}

private final class NoopRemoteCameraCaptureRecorder: RemoteCameraCaptureRecording {
    private(set) var startCount = 0
    let completion: MediaWriterCompletion

    init(completion: MediaWriterCompletion) {
        self.completion = completion
    }

    func startRemoteCamera(take: RecordingTake, settings: RecordingSettings, hostTimelineStartTime: UInt64) async throws {
        startCount += 1
    }

    func pauseRemoteCamera() {}
    func resumeRemoteCamera() {}
    func stopRemoteCamera(take: RecordingTake, settings: RecordingSettings) async throws -> MediaWriterCompletion {
        completion
    }
}

private final class NoopMicrophoneCaptureRecorder: MicrophoneCaptureRecording {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .wrote() }
}

private final class NoopSystemAudioCaptureRecorder: SystemAudioCaptureRecording {
    func start(url: URL, settings: RecordingSettings, timelineStartTime: CMTime?) async throws {}
    func pause() {}
    func resume() {}
    func stop() async throws -> MediaWriterCompletion { .wrote() }
}

private final class StopFailureLiveCompositedRecorder: LiveCompositedRecording {
    var onCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onScreenPreviewFrame: ScreenPreviewer.FrameHandler?
    let completion: MediaWriterCompletion
    let error: Error

    init(completion: MediaWriterCompletion, error: Error) {
        self.completion = completion
        self.error = error
    }

    func start(
        take: RecordingTake,
        settings: RecordingSettings,
        filter pickedFilter: SCContentFilter?,
        prerollSeconds: Int,
        prerollHandler: (@MainActor (Int) -> Void)?
    ) async throws {}

    func pause() {}
    func resume() {}

    func stop() async throws -> MediaWriterCompletion {
        throw CaptureSourceStopFailure(completion: completion, underlyingError: error)
    }

    func updateScene(_ scene: RecordingScene, transition: RecordingSceneTransition) {}
    func updateScreenCapture(settings: RecordingSettings, filter pickedFilter: SCContentFilter?) async throws {}
}
