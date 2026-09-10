import XCTest
@testable import BlitzRecorderApp

final class MotionOptOutTests: XCTestCase {
    private var zoom: ScreenZoomTrack {
        .init(keyframes: [
            .init(time: 0, amount: 0, position: .zero),
            .init(time: 1, amount: 0.5, position: CGPoint(x: 0.4, y: 0.6)),
            .init(time: 2, amount: 0, position: .zero)
        ], generatedFromCursor: true, intensity: 2)
    }

    func testDisablingZoomKeepsItsPointsAndRestoresTheSameMotionWhenEnabled() {
        let original = zoom
        var disabled = original
        disabled.isEnabled = false
        XCTAssertFalse(disabled.isActive)
        XCTAssertFalse(disabled.isEmpty)
        XCTAssertEqual(disabled.keyframes, original.keyframes)
        XCTAssertEqual(disabled.intensity, original.intensity)
        for time in stride(from: 0.0, through: 2, by: 0.1) {
            XCTAssertEqual(disabled.sample(at: time), .none)
        }
        XCTAssertFalse(disabled.hasVariation(in: 0...2))
        XCTAssertTrue(disabled.keyframeTimes.isEmpty)
        disabled.isEnabled = true
        XCTAssertEqual(disabled, original)
        XCTAssertEqual(disabled.sample(at: 1), original.sample(at: 1))
    }

    func testDisabledZoomSurvivesReopeningWithoutDiscardingOtherEdits() throws {
        var edits = TimelineEdits.empty
        edits.zoom = zoom
        edits.zoom.isEnabled = false
        edits.cameraFollowsZoom = true
        edits.cursorStyle = .init(smoothed: false, scale: 1, emphasizesClicks: false)
        let data = try JSONEncoder().encode(RecordingProject.TimelineEditsSnapshot(edits))
        let reopened = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self, from: data)
        XCTAssertEqual(reopened.edits, edits)
        XCTAssertFalse(reopened.isEmpty)
        XCTAssertFalse(reopened.edits.zoom.isActive)
    }

    func testLegacyZoomWithoutAnEnabledFlagKeepsItsAppearance() throws {
        let original = zoom
        let data = try JSONEncoder().encode(RecordingProject.ZoomTrackSnapshot(original))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isEnabled")
        let legacy = try JSONDecoder().decode(RecordingProject.ZoomTrackSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.track, original)
        XCTAssertTrue(legacy.track.isActive)
    }

    func testTurningZoomOffPreservesSourceFramingAndStopsCameraMotion() {
        var scene = RecordingScene(settings: RecordingSettings())
        scene.enabledSources = [.screen, .camera]
        scene.sceneLayout = SceneLayout(
            screenFrame: CGRect(x: 0, y: 0, width: 1, height: 1),
            cameraFrame: CGRect(x: 0.7, y: 0.05, width: 0.25, height: 0.3)
        )
        scene.screenCropAmount = CGPoint(x: 0.1, y: 0.2)
        scene.screenCropPosition = CGPoint(x: 0.2, y: -0.3)
        var edits = TimelineEdits.empty
        edits.zoom = zoom
        edits.cameraFollowsZoom = true
        XCTAssertNotEqual(TimelineOverlayRenderer.scene(.init(scene: scene, edits: edits, time: 1)), scene)
        edits.zoom.isEnabled = false
        for time in [0.0, 0.5, 1, 1.5, 2] {
            XCTAssertEqual(TimelineOverlayRenderer.scene(.init(scene: scene, edits: edits, time: time)), scene)
        }
        edits.zoom.isEnabled = true
        edits.cameraFollowsZoom = false
        let stillCamera = TimelineOverlayRenderer.scene(.init(scene: scene, edits: edits, time: 1))
        XCTAssertEqual(stillCamera.sceneLayout.cameraFrame, scene.sceneLayout.cameraFrame)
        XCTAssertNotEqual(stillCamera.screenCropAmount, scene.screenCropAmount)
    }

    func testDisabledEffectsDoNotRunTheirThumbnailAnimations() {
        for effect in [EditorMotionEffect.smoothing(false), .clicks(false), .cameraFollow(false),
                       .zoom(amount: 2, enabled: false), .cursorSize(2)] {
            XCTAssertFalse(effect.allowsAnimation)
        }
        for effect in [EditorMotionEffect.smoothing(true), .clicks(true), .cameraFollow(true),
                       .zoom(amount: 2, enabled: true)] {
            XCTAssertTrue(effect.allowsAnimation)
        }
    }
}
