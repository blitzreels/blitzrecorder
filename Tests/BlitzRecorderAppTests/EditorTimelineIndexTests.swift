import CoreGraphics
import CoreMedia
@testable import BlitzRecorderApp
import XCTest

final class EditorTimelineIndexTests: XCTestCase {
    func testEventIndexFindsLastEventAtOrBeforeTime() {
        let settings = RecordingSettings()
        let events = [
            RecordingSceneEvent(time: 0, scene: RecordingScene(settings: settings)),
            RecordingSceneEvent(time: 1.5, scene: RecordingScene(settings: settings)),
            RecordingSceneEvent(time: 4, scene: RecordingScene(settings: settings))
        ]
        XCTAssertEqual(EditorTimelineIndex.eventIndex(at: 0, in: events), 0)
        XCTAssertEqual(EditorTimelineIndex.eventIndex(at: 1.4, in: events), 0)
        XCTAssertEqual(EditorTimelineIndex.eventIndex(at: 1.5, in: events), 1)
        XCTAssertEqual(EditorTimelineIndex.eventIndex(at: 3.9, in: events), 1)
        XCTAssertEqual(EditorTimelineIndex.eventIndex(at: 10, in: events), 2)
        XCTAssertEqual(EditorTimelineIndex.eventIndex(at: 0, in: []), 0)
    }

    func testBoundarySearchSkipsSlackWindow() {
        let times: [Double] = [0, 1, 2, 5, 9]
        XCTAssertEqual(EditorTimelineIndex.previousBoundary(at: 2.1, in: times), 1)
        XCTAssertEqual(EditorTimelineIndex.previousBoundary(at: 0.1, in: times), 0)
        XCTAssertEqual(EditorTimelineIndex.nextBoundary(at: 1.9, in: times, duration: 12), 5)
        XCTAssertEqual(EditorTimelineIndex.nextBoundary(at: 9, in: times, duration: 12), 12)
    }

    func testSegmentIndexFallsBackToLastWhenTimeMisses() {
        let settings = RecordingSettings()
        let scene = RecordingScene(settings: settings)
        let segments = [
            FinalExportRenderSegment(
                timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)),
                scene: scene,
                activeLayerOrder: [.screen]
            ),
            FinalExportRenderSegment(
                timeRange: CMTimeRange(
                    start: CMTime(seconds: 2, preferredTimescale: 600),
                    duration: CMTime(seconds: 3, preferredTimescale: 600)
                ),
                scene: scene,
                activeLayerOrder: [.camera]
            )
        ]
        XCTAssertEqual(
            EditorTimelineIndex.containingSegmentIndex(
                at: CMTime(seconds: 1, preferredTimescale: 600),
                in: segments
            ),
            0
        )
        XCTAssertEqual(
            EditorTimelineIndex.containingSegmentIndex(
                at: CMTime(seconds: 4, preferredTimescale: 600),
                in: segments
            ),
            1
        )
        XCTAssertNil(
            EditorTimelineIndex.containingSegmentIndex(
                at: CMTime(seconds: 10, preferredTimescale: 600),
                in: segments
            )
        )
        XCTAssertEqual(
            EditorTimelineIndex.segmentIndex(
                at: CMTime(seconds: 10, preferredTimescale: 600),
                in: segments
            ),
            1
        )
        XCTAssertNil(EditorTimelineIndex.segmentIndex(at: .zero, in: []))
    }
}

final class SceneLayoutFrameTests: XCTestCase {
    func testFrameAccessorsRoundTrip() {
        var layout = SceneLayout()
        let screen = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let camera = CGRect(x: 0.5, y: 0.1, width: 0.2, height: 0.2)
        layout.setFrame(screen, for: .screen)
        layout.setFrame(camera, for: .camera)
        XCTAssertEqual(layout.frame(for: .screen), screen)
        XCTAssertEqual(layout.frame(for: .camera), camera)
    }

    func testScaledAroundCenterClampsRatio() {
        let frame = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        XCTAssertEqual(SceneLayout.scaledAroundCenter(frame, scale: 1), frame)
        let half = SceneLayout.scaledAroundCenter(frame, scale: 0.5)
        XCTAssertEqual(half.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(half.midX, frame.midX, accuracy: 0.0001)
        let floor = SceneLayout.scaledAroundCenter(frame, scale: 0.01)
        XCTAssertEqual(floor.width, frame.width * 0.1, accuracy: 0.0001)
    }
}

final class EditorLayoutDraftTests: XCTestCase {
    func testMoveAndResizeMutateDraftWithoutTouchingStartLayout() {
        var scene = RecordingScene(settings: RecordingSettings())
        scene.sceneLayout.screenFrame = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.4)
        var draft = EditorLayoutDraft(
            eventIndex: 0,
            startLayout: scene.sceneLayout,
            startCameraContentMode: scene.cameraContentMode,
            scene: scene
        )
        XCTAssertFalse(draft.hasLayoutChanges)
        draft.applyMove(kind: .screen, translation: CGSize(width: 0.05, height: 0.1))
        XCTAssertTrue(draft.hasLayoutChanges)
        XCTAssertEqual(draft.startLayout.screenFrame, CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.4))
        XCTAssertEqual(draft.scene.sceneLayout.screenFrame.origin.x, 0.15, accuracy: 0.0001)
        XCTAssertEqual(draft.scene.sceneLayout.screenFrame.origin.y, 0.1, accuracy: 0.0001)
    }
}

final class EditorCanvasSessionTests: XCTestCase {
    func testEnsureDraftSeeksPastTransition() throws {
        var scene = RecordingScene(settings: RecordingSettings())
        scene.enabledSources = [.screen]
        scene.sceneLayout.screenFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let events = [
            RecordingSceneEvent(
                time: 0,
                scene: scene,
                transition: RecordingSceneTransition(duration: 0.5)
            )
        ]
        let result = try XCTUnwrap(EditorCanvasSession.ensureDraft(
            existing: nil,
            eventIndex: 0,
            events: events,
            currentTime: 0.1,
            duration: 10,
            isPlaybackReady: true
        ))
        XCTAssertEqual(result.seekTime ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.draft.eventIndex, 0)
        XCTAssertNil(EditorCanvasSession.ensureDraft(
            existing: nil,
            eventIndex: 0,
            events: events,
            currentTime: 0.1,
            duration: 10,
            isPlaybackReady: false
        ))
    }

    func testCommitDiscardsUnchangedAndFailsClosed() {
        XCTAssertEqual(
            EditorCanvasSession.commit(hasChanges: false, succeeded: true, projectChanged: true),
            .discard
        )
        XCTAssertEqual(
            EditorCanvasSession.commit(hasChanges: true, succeeded: false, projectChanged: false),
            .failed
        )
        XCTAssertEqual(
            EditorCanvasSession.commit(hasChanges: true, succeeded: true, projectChanged: false),
            .revertUnchanged
        )
        XCTAssertEqual(
            EditorCanvasSession.commit(hasChanges: true, succeeded: true, projectChanged: true),
            .apply
        )
    }
}

final class RecorderStudioEditPolicyTests: XCTestCase {
    func testEditAllowedOnlyWhileIdleRecordingOrPaused() {
        XCTAssertTrue(RecorderStudioEditPolicy.canEdit(state: .idle))
        XCTAssertTrue(RecorderStudioEditPolicy.canEdit(state: .recording))
        XCTAssertTrue(RecorderStudioEditPolicy.canEdit(state: .paused))
        XCTAssertFalse(RecorderStudioEditPolicy.canEdit(state: .starting))
        XCTAssertFalse(RecorderStudioEditPolicy.canEdit(state: .finishing))
    }
}

final class ScreenSourceCatalogTests: XCTestCase {
    func testReadableNamesCollapseWhitespaceAndDropGenerics() {
        XCTAssertEqual(ScreenSourceCatalog.readableApplicationName("  Google\nChrome  "), "Google Chrome")
        XCTAssertNil(ScreenSourceCatalog.readableApplicationName("Application"))
        XCTAssertEqual(ScreenSourceCatalog.readableWindowTitle("  Project\nSettings  "), "Project Settings")
        XCTAssertNil(ScreenSourceCatalog.readableWindowTitle("Untitled window"))
        XCTAssertEqual(
            ScreenSourceCatalog.applicationKey(bundleIdentifier: "com.apple.Safari", processID: 1, applicationName: "Safari"),
            "bundle:com.apple.Safari"
        )
    }
}
