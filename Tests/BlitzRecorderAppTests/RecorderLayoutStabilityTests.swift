import XCTest
@testable import BlitzRecorderApp

final class RecorderLayoutStabilityTests: XCTestCase {
    @MainActor
    func testIdleFramesCannotAlternateWithRecordingFrames() throws {
        let fixture = try SyntheticRecording()
        let studio = RecorderStudioConfiguration(defaults: nil)
        let runtime = RecorderCaptureRuntime(studio: studio, permissionGate: PermissionGate(),
            recents: ScreenSourcePickerRecents(defaults: .standard))
        runtime.idleCaptureResourcesEnabled = true
        let sample = try fixture.videoSample(at: 0)
        let idleFrame = ScreenPreviewFrame(sampleBuffer: sample, width: 640, height: 527,
            sourceAspectRatio: 1.2149)
        let recordingFrame = ScreenPreviewFrame(sampleBuffer: sample, width: 640, height: 360,
            sourceAspectRatio: 16.0 / 9)
        var idleDeliveries = 0
        var recordingDeliveries = 0
        let idleHandler = runtime.idleScreenPreviewHandler { _ in idleDeliveries += 1 }
        runtime.onLiveScreenPreviewFrame = { _ in recordingDeliveries += 1 }
        idleHandler(idleFrame)
        XCTAssertEqual(idleDeliveries, 1)
        XCTAssertTrue(runtime.recordingSession.beginPreparation(.init(outputDirectoryAccess:
            OutputDirectoryAccess(url: fixture.root, usesSecurityScopedBookmark: false))))
        runtime.recordingSession.noteActiveTake(.init(take: fixture.take, settings: fixture.settings))

        for phase in 0..<3 {
            if phase == 1 { runtime.recordingSession.markRecordingStarted() }
            if phase == 2 { XCTAssertTrue(runtime.recordingSession.pause()) }
            for _ in 0..<24 {
                runtime.forwardLiveScreenFrame(.init(frame: recordingFrame, producer: "screen recorder"))
                idleHandler(idleFrame)
            }
            XCTAssertEqual(studio.currentPickedScreenSourceAspectRatio ?? 0, 16.0 / 9, accuracy: 0.001)
        }
        XCTAssertEqual(idleDeliveries, 1, "The idle stream must not replace recording pixels or geometry")
        XCTAssertEqual(recordingDeliveries, 72)
    }

    @MainActor
    func testReplacedAndStoppedIdlePreviewCannotDeliverStaleFrames() async throws {
        let fixture = try SyntheticRecording()
        let runtime = RecorderCaptureRuntime(studio: RecorderStudioConfiguration(defaults: nil),
            permissionGate: PermissionGate(), recents: ScreenSourcePickerRecents(defaults: .standard))
        runtime.idleCaptureResourcesEnabled = true
        let frame = ScreenPreviewFrame(sampleBuffer: try fixture.videoSample(at: 0), width: 640,
            height: 360, sourceAspectRatio: 16.0 / 9)
        var oldDeliveries = 0
        var currentDeliveries = 0
        let oldHandler = runtime.idleScreenPreviewHandler { _ in oldDeliveries += 1 }
        let currentHandler = runtime.idleScreenPreviewHandler { _ in currentDeliveries += 1 }
        oldHandler(frame)
        currentHandler(frame)
        XCTAssertEqual(oldDeliveries, 0)
        XCTAssertEqual(currentDeliveries, 1)
        await runtime.stopScreenPreview()
        currentHandler(frame)
        XCTAssertEqual(currentDeliveries, 1)
    }
}
