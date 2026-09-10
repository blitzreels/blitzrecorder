import MediaPlayer
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class NowPlayingControllerTests: XCTestCase {
    func testTransportControlsOperateOnTheActivePlayback() {
        let controller = NowPlayingController(publishesToSystem: false)
        let playback = PlaybackStub()
        controller.activate(.init(playback: playback, title: "Project"))

        XCTAssertEqual(controller.perform(.play), .success)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(controller.perform(.play), .success)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(controller.perform(.pause), .success)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(controller.perform(.toggle), .success)
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.perform(.rate(.oneAndAHalf)), .success)
        XCTAssertEqual(playback.playbackRate, .oneAndAHalf)
    }

    func testSeekingClampsToTheEditedTimelineAndRejectsInvalidPositions() {
        let controller = NowPlayingController(publishesToSystem: false)
        let playback = PlaybackStub()
        controller.activate(.init(playback: playback, title: "Project"))

        XCTAssertEqual(controller.perform(.skip(-10)), .success)
        XCTAssertEqual(playback.nowPlayingTime, 0)
        XCTAssertEqual(controller.perform(.seek(500)), .success)
        XCTAssertEqual(playback.nowPlayingTime, 60)
        XCTAssertEqual(controller.perform(.skip(-10)), .success)
        XCTAssertEqual(controller.elapsedTime, 50)
        XCTAssertEqual(controller.perform(.seek(.nan)), .commandFailed)
        XCTAssertEqual(controller.perform(.skip(.infinity)), .commandFailed)
        XCTAssertEqual(playback.nowPlayingTime, 50)
    }

    func testSwitchingOwnersPausesPreviousPlaybackAndIgnoresItsTeardown() {
        let controller = NowPlayingController(publishesToSystem: false)
        let previous = PlaybackStub()
        let current = PlaybackStub()
        controller.activate(.init(playback: previous, title: "Previous"))
        controller.perform(.play)

        controller.activate(.init(playback: current, title: "Current"))
        controller.deactivate(previous)

        XCTAssertFalse(previous.isPlaying)
        XCTAssertTrue(controller.hasMedia)
        XCTAssertEqual(controller.title, "Current")
        controller.perform(.play)
        XCTAssertTrue(current.isPlaying)
        XCTAssertFalse(previous.isPlaying)
    }

    func testStartingRecordingClearsRemotePlaybackAndCannotResumeIt() {
        let controller = NowPlayingController(publishesToSystem: false)
        let playback = PlaybackStub()
        controller.activate(.init(playback: playback, title: "Project"))
        controller.perform(.play)

        controller.suspendForRecording()

        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(controller.hasMedia)
        XCTAssertEqual(controller.perform(.play), .noActionableNowPlayingItem)
        XCTAssertFalse(playback.isPlaying)
    }

    func testClosedOrUnavailablePlaybackRejectsRemoteCommands() {
        let controller = NowPlayingController(publishesToSystem: false)
        var playback: PlaybackStub? = PlaybackStub()
        controller.activate(.init(playback: playback!, title: "Project"))
        playback?.isReady = false

        XCTAssertEqual(controller.perform(.play), .noActionableNowPlayingItem)
        playback = nil
        controller.refresh()

        XCTAssertFalse(controller.hasMedia)
        XCTAssertTrue(controller.title.isEmpty)
        XCTAssertEqual(controller.perform(.toggle), .noActionableNowPlayingItem)
    }
}

@MainActor
private final class PlaybackStub: NowPlayingPlayback {
    var isReady = true
    var isPlaying = false
    var playbackRate = EditorPlaybackRate.normal
    var nowPlayingDuration: Double = 60
    var nowPlayingTime: Double = 5

    func togglePlayback() {
        isPlaying.toggle()
    }

    func pauseForEditing() {
        isPlaying = false
    }

    func seekFromNowPlaying(to seconds: Double) {
        nowPlayingTime = seconds
    }

    func setPlaybackRate(_ rate: EditorPlaybackRate) {
        playbackRate = rate
    }
}
