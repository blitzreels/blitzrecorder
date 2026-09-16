import XCTest
@testable import BlitzRecorderApp

final class EditorProjectRefreshPolicyTests: XCTestCase {
    func testPausedEditorDoesNotRunDisplayLink() {
        XCTAssertFalse(EditorDisplayLinkPolicy.shouldRun(EditorDisplayLinkRequest(
            isAttachedToWindow: true,
            isPlaying: false
        )))
    }

    func testPlayingEditorRunsDisplayLinkWhileAttached() {
        XCTAssertTrue(EditorDisplayLinkPolicy.shouldRun(EditorDisplayLinkRequest(
            isAttachedToWindow: true,
            isPlaying: true
        )))
    }

    func testSceneOnlyProjectSaveKeepsActivePlayback() {
        let kind = EditorProjectRefreshPolicy.kind(for: EditorProjectRefreshRequest(
            hasActivePlayback: true,
            isSameProject: true,
            hasSameMedia: true
        ))

        XCTAssertEqual(kind, .sceneTimeline)
    }

    func testMediaChangeReloadsPlayback() {
        let kind = EditorProjectRefreshPolicy.kind(for: EditorProjectRefreshRequest(
            hasActivePlayback: true,
            isSameProject: true,
            hasSameMedia: false
        ))

        XCTAssertEqual(kind, .fullPlayback)
    }

    func testPlaybackClockUsesLongestSourceInsteadOfShortAudio() {
        let index = EditorPlaybackClockSelection.index(for: [0.5, 3, 2.8])

        XCTAssertEqual(index, 1)
    }

    func testPlaybackClockIgnoresInvalidDurations() {
        let index = EditorPlaybackClockSelection.index(for: [.nan, 2, .infinity])

        XCTAssertEqual(index, 1)
    }

    func testPlaybackRatesExposeExpectedEditorChoices() {
        XCTAssertEqual(EditorPlaybackRate.allCases.map(\.displayName), ["0.5×", "1×", "1.5×", "2×", "2.5×"])
        XCTAssertEqual(EditorPlaybackRate.allCases.map(\.rawValue), [0.5, 1, 1.5, 2, 2.5])
    }

    func testPlaybackRateIncrementStopsAtTwoAndAHalfSpeed() {
        XCTAssertEqual(EditorPlaybackRate.half.nextFaster, .normal)
        XCTAssertEqual(EditorPlaybackRate.normal.nextFaster, .oneAndAHalf)
        XCTAssertEqual(EditorPlaybackRate.oneAndAHalf.nextFaster, .double)
        XCTAssertEqual(EditorPlaybackRate.double.nextFaster, .twoAndAHalf)
        XCTAssertEqual(EditorPlaybackRate.twoAndAHalf.nextFaster, .twoAndAHalf)
    }

    func testPlayingClockSkipsRedundantTimePublishesInsideTheSameScene() {
        let update = EditorPlaybackClockPublish.apply(.init(
            nextTime: 1.05,
            currentTime: 1.0,
            nextIsPlaying: true,
            isPlaying: true,
            isSameSceneSegment: true
        ))
        XCTAssertNil(update.currentTime)
        XCTAssertNil(update.isPlaying)
        XCTAssertFalse(update.shouldRefreshSceneCache)
    }

    func testPlayingClockPublishesWhenTheSceneSegmentChanges() {
        let update = EditorPlaybackClockPublish.apply(.init(
            nextTime: 4.0,
            currentTime: 1.0,
            nextIsPlaying: true,
            isPlaying: true,
            isSameSceneSegment: false
        ))
        XCTAssertEqual(update.currentTime, 4.0)
        XCTAssertNil(update.isPlaying)
        XCTAssertTrue(update.shouldRefreshSceneCache)
    }

    func testPausedClockPublishesSeekedTimeAndSkipsUnchangedTime() {
        let seeked = EditorPlaybackClockPublish.apply(.init(
            nextTime: 2.5,
            currentTime: 1.0,
            nextIsPlaying: false,
            isPlaying: false,
            isSameSceneSegment: true
        ))
        XCTAssertEqual(seeked.currentTime, 2.5)
        XCTAssertNil(seeked.isPlaying)

        let unchanged = EditorPlaybackClockPublish.apply(.init(
            nextTime: 2.50005,
            currentTime: 2.5,
            nextIsPlaying: false,
            isPlaying: false,
            isSameSceneSegment: true
        ))
        XCTAssertNil(unchanged.currentTime)
        XCTAssertNil(unchanged.isPlaying)
    }

    func testClockPublishesPlayStateOnlyWhenItChanges() {
        let started = EditorPlaybackClockPublish.apply(.init(
            nextTime: 1.0,
            currentTime: 1.0,
            nextIsPlaying: true,
            isPlaying: false,
            isSameSceneSegment: true
        ))
        XCTAssertEqual(started.isPlaying, true)
        XCTAssertNil(started.currentTime)

        let stopped = EditorPlaybackClockPublish.apply(.init(
            nextTime: 1.2,
            currentTime: 1.0,
            nextIsPlaying: false,
            isPlaying: true,
            isSameSceneSegment: true
        ))
        XCTAssertEqual(stopped.isPlaying, false)
        XCTAssertEqual(stopped.currentTime, 1.2)
    }
}
