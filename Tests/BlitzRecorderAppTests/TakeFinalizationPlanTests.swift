@testable import BlitzRecorderApp
import Foundation
import XCTest

final class TakeFinalizationPlanTests: XCTestCase {
    func testPlansTransparentCameraOnlySaveBeforeVideoMediaCheck() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.removesCameraBackgroundAfterRecording = true
        let take = makeTake()

        let plan = TakeFinalizationPlan(
            take: take,
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [:]),
            fileExists: { $0 == take.cameraURL }
        )

        XCTAssertEqual(plan.action, .saveTransparentCameraOnly)
    }

    func testPlansRecoveryWhenNoVideoMediaWasCaptured() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .microphone]
        let plan = TakeFinalizationPlan(
            take: makeTake(),
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [.microphone: .wrote()]),
            fileExists: { _ in true }
        )

        XCTAssertEqual(plan.action, .recoverNoVideo(reason: "No video frames captured"))
    }

    func testPlansFinalExportWhenVideoMediaExists() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen, .microphone]
        let plan = TakeFinalizationPlan(
            take: makeTake(),
            settings: settings,
            captureSummary: CaptureSourceRunSummary(completions: [.screen: .wrote()]),
            fileExists: { _ in true }
        )

        XCTAssertEqual(plan.action, .exportFinalVideo)
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
