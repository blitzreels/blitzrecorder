import XCTest

@testable import BlitzRecorderApp

@MainActor
final class EditorPlaybackVolumeTests: XCTestCase {
    func testMuteRestoresLastAudibleLevel() {
        let playback = EditorPlaybackController()
        playback.setPlaybackVolume(0.35)
        playback.togglePlaybackMute()
        XCTAssertEqual(playback.playbackVolume, 0)
        playback.togglePlaybackMute()
        XCTAssertEqual(playback.playbackVolume, 0.35)
    }

    func testDraggingToSilencePreservesPreviousLevelAcrossPlayerTeardown() {
        let playback = EditorPlaybackController()
        playback.setPlaybackVolume(0.6)
        playback.setPlaybackVolume(0)
        playback.teardown()
        playback.togglePlaybackMute()
        XCTAssertEqual(playback.playbackVolume, 0.6)
        XCTAssertTrue(playback.mutedSources.isEmpty)
        XCTAssertEqual(playback.edits, .empty)
    }

    func testVolumeClampsRangeAndIgnoresInvalidValues() {
        let playback = EditorPlaybackController()
        playback.setPlaybackVolume(2)
        XCTAssertEqual(playback.playbackVolume, 1)
        playback.setPlaybackVolume(-1)
        XCTAssertEqual(playback.playbackVolume, 0)
        playback.setPlaybackVolume(0.4)
        playback.setPlaybackVolume(.nan)
        playback.setPlaybackVolume(.infinity)
        XCTAssertEqual(playback.playbackVolume, 0.4)
    }
}
