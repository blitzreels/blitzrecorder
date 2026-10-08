import XCTest
@testable import BlitzRecorderApp

final class AudioRecordingPauseControllerTests: XCTestCase {
    func testResumeDoesNotWaitForTheNativePausedFlag() {
        let output = DelayedAudioFileOutput()
        var controller = AudioRecordingPauseController()

        XCTAssertTrue(controller.pause(output))
        XCTAssertTrue(controller.isPaused)
        XCTAssertFalse(output.isRecordingPaused)
        XCTAssertTrue(controller.resume(output))
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(output.pauseRequests, 1)
        XCTAssertEqual(output.resumeRequests, 1)
    }

    func testRepeatedRequestsDoNotDuplicateNativeCommands() {
        let output = DelayedAudioFileOutput()
        var controller = AudioRecordingPauseController()

        XCTAssertFalse(controller.resume(output))
        for _ in 0..<3 {
            XCTAssertTrue(controller.pause(output))
            XCTAssertFalse(controller.pause(output))
            XCTAssertTrue(controller.resume(output))
            XCTAssertFalse(controller.resume(output))
        }
        XCTAssertEqual(output.pauseRequests, 3)
        XCTAssertEqual(output.resumeRequests, 3)
    }

    func testInactiveOutputCannotPause() {
        let output = DelayedAudioFileOutput()
        output.isRecording = false
        var controller = AudioRecordingPauseController()

        XCTAssertFalse(controller.pause(output))
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(output.pauseRequests, 0)
    }

    func testStaleNativePausedFlagDoesNotResumeTwice() {
        let output = DelayedAudioFileOutput()
        var controller = AudioRecordingPauseController()

        XCTAssertTrue(controller.pause(output))
        output.isRecordingPaused = true
        XCTAssertTrue(controller.resume(output))
        XCTAssertFalse(controller.resume(output))
        XCTAssertEqual(output.resumeRequests, 1)
    }
}

private final class DelayedAudioFileOutput: AudioFilePauseRecording {
    var isRecording = true
    var isRecordingPaused = false
    private(set) var pauseRequests = 0
    private(set) var resumeRequests = 0

    func pauseRecording() { pauseRequests += 1 }
    func resumeRecording() { resumeRequests += 1 }
}
