import CoreImage
import XCTest
@testable import BlitzRecorderApp

final class CursorPresentationTests: XCTestCase {
    func testLegacyCursorTrackNeverDrawsASecondCursor() throws {
        let data = Data(#"{"version":1,"samples":[{"time":1,"x":0.2,"y":0.3,"clicked":true}]}"#.utf8)
        let track = try JSONDecoder().decode(RecordingCursorTrack.self, from: data)
        XCTAssertFalse(track.supportsPresentation)
        let presentation = CursorPresentationTrack(.init(track: track, trimOffset: 0))
        XCTAssertNil(presentation.sample(.init(time: 1, style: .standard)))
    }

    func testCursorAndCameraEditsRoundTripAndLegacyProjectsKeepTheirAppearance() throws {
        let legacy = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.edits, .empty)
        var edits = TimelineEdits.empty
        edits.cursorStyle = .init(smoothed: false, scale: 2.5, emphasizesClicks: false)
        edits.cameraFollowsZoom = true
        let snapshot = RecordingProject.TimelineEditsSnapshot(edits)
        XCTAssertFalse(snapshot.isEmpty)
        let reopened = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
                                               from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(reopened.edits, edits)
    }

    func testSmoothingReducesJitterWithoutMovingTheClickTarget() throws {
        let samples = (0..<30).map { index in
            RecordingCursorSample(time: Double(index) / 60, x: index.isMultiple(of: 2) ? 0.49 : 0.51,
                                  y: 0.5, clicked: index == 15, rendered: true)
        }
        let track = CursorPresentationTrack(.init(track: .init(version: 2, samples: samples), trimOffset: 0))
        let smooth = try XCTUnwrap(track.sample(.init(time: 10.0 / 60, style: .standard)))
        let raw = try XCTUnwrap(track.sample(.init(time: 10.0 / 60, style: .init(smoothed: false))))
        XCTAssertLessThan(abs(smooth.position.x - 0.5), abs(raw.position.x - 0.5) / 2)
        let click = try XCTUnwrap(track.sample(.init(time: 15.0 / 60, style: .standard)))
        XCTAssertEqual(click.position.x, 0.51, accuracy: 0.0001)
        XCTAssertEqual(click.clickAge, 0, accuracy: 0.0001)
    }

    func testSeekingAndCutsUseCaptureTimeAfterTrim() throws {
        let samples = (0..<120).map { index in
            RecordingCursorSample(time: Double(index) / 60, x: Double(index) / 120,
                                  y: 0.3, clicked: index == 90, rendered: true)
        }
        let track = CursorPresentationTrack(.init(track: .init(version: 2, samples: samples), trimOffset: 0.5))
        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(1.5), cuts: [
            .init(start: 0.2, end: 0.7, kind: .manual, source: .user)
        ])
        let time = map.takeSeconds(forOutputSeconds: 0.5)
        let expected = try XCTUnwrap(track.sample(.init(time: time, style: .standard)))
        _ = track.sample(.init(time: 1.3, style: .standard))
        _ = track.sample(.init(time: 0.1, style: .standard))
        XCTAssertEqual(track.sample(.init(time: time, style: .standard)), expected)
        XCTAssertEqual(expected.position.x, 0.75, accuracy: 0.001)
        XCTAssertEqual(expected.clickAge, 0, accuracy: 0.001)
    }

    func testCursorHidesOutsideCaptureAndDoesNotBridgeSourceChangesOrGaps() throws {
        let track = CursorPresentationTrack(.init(track: .init(version: 2, samples: [
            .init(time: 0, x: 0.2, y: 0.3, clicked: false, rendered: true),
            .init(time: 0.05, x: 1.1, y: 0.3, clicked: false, visible: false, rendered: true),
            .init(time: 0.1, x: 0.8, y: 0.3, clicked: false, rendered: false, segment: 1),
            .init(time: 1, x: 0.8, y: 0.3, clicked: false, rendered: true, segment: 2)
        ]), trimOffset: 0))
        XCTAssertEqual(track.sample(.init(time: 0.02, style: .standard))?.position.x, 0.2)
        for time in [-0.1, 0.05, 0.1, 0.5, 1.3] {
            XCTAssertNil(track.sample(.init(time: time, style: .standard)))
        }
        XCTAssertEqual(track.sample(.init(time: 1, style: .standard))?.position.x, 0.8)
    }

    func testSpriteKeepsItsHotspotWhenResizedAndZoomed() throws {
        let sample = CursorPresentationSample(position: CGPoint(x: 0.7, y: 0.2), clickAge: 1, rotation: 0)
        let sourceFrame = CGRect(x: -400, y: -150, width: 2400, height: 1350)
        for scale in [0.75, 1.5, 3] {
            let sprite = try XCTUnwrap(CursorPresentationRenderer.sprite(.init(
                sample: sample, style: .init(scale: scale), sourceFrame: sourceFrame)))
            XCTAssertEqual(sprite.frame.midX, 1280, accuracy: 0.01)
            XCTAssertEqual(sprite.frame.midY, 120, accuracy: 0.01)
        }
    }

    func testExportPlacesCursorInTheSameUpperLeftCoordinatesAsPreview() throws {
        let sample = CursorPresentationSample(position: CGPoint(x: 0.2, y: 0.25), clickAge: 1, rotation: 0)
        let style = CursorPresentationStyle(scale: 3)
        let extent = CGRect(x: 0, y: 0, width: 640, height: 480)
        let background = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: extent)
        let image = CursorPresentationRenderer.composite(.init(image: background, sample: sample, style: style))
        let sprite = try XCTUnwrap(CursorPresentationRenderer.sprite(.init(
            sample: sample, style: style, sourceFrame: extent)))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        var cursorPixel = [UInt8](repeating: 0, count: 4)
        let cursorPoint = CGPoint(x: sprite.frame.midX + 3, y: extent.height - sprite.frame.midY - 9)
        context.render(image, toBitmap: &cursorPixel, rowBytes: 4,
                       bounds: CGRect(origin: cursorPoint, size: CGSize(width: 1, height: 1)),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        XCTAssertLessThan(cursorPixel[0], 100)
        XCTAssertLessThan(cursorPixel[1], 100)
        var oppositePixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &oppositePixel, rowBytes: 4,
                       bounds: CGRect(x: cursorPoint.x, y: 120, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        XCTAssertGreaterThan(oppositePixel[0], 240)
        XCTAssertLessThan(oppositePixel[1], 10)
    }

    func testCameraMotionKeepsTheCornerAndRestoresOriginalFrame() {
        for frame in [CGRect(x: 0.7, y: 0.65, width: 0.25, height: 0.3),
                      CGRect(x: 0.05, y: 0.05, width: 0.25, height: 0.3)] {
            var scene = RecordingScene(settings: RecordingSettings())
            scene.enabledSources = [.screen, .camera]
            scene.sceneLayout = SceneLayout(screenFrame: CGRect(x: 0, y: 0, width: 1, height: 1), cameraFrame: frame)
            var edits = TimelineEdits.empty
            edits.cameraFollowsZoom = true
            edits.zoom = .init(keyframes: [
                .init(time: 0, amount: 0, position: .zero),
                .init(time: 1, amount: 0.5, position: .zero),
                .init(time: 2, amount: 0, position: .zero)
            ], generatedFromCursor: true, intensity: 2)
            let peak = TimelineOverlayRenderer.scene(.init(scene: scene, edits: edits, time: 1)).sceneLayout.cameraFrame
            XCTAssertEqual(peak.width, frame.width * 0.75, accuracy: 0.001)
            XCTAssertEqual(frame.midX < 0.5 ? peak.minX : peak.maxX,
                           frame.midX < 0.5 ? frame.minX : frame.maxX, accuracy: 0.001)
            XCTAssertEqual(frame.midY < 0.5 ? peak.minY : peak.maxY,
                           frame.midY < 0.5 ? frame.minY : frame.maxY, accuracy: 0.001)
            XCTAssertEqual(TimelineOverlayRenderer.scene(.init(scene: scene, edits: edits, time: 2)).sceneLayout.cameraFrame, frame)
        }
    }

    func testCameraMotionLeavesSplitAndFullCameraLayoutsAlone() {
        for preset in [ScenePreset.stackedHalves, .webcamFullscreen] {
            var scene = RecordingScene(settings: RecordingSettings())
            scene.sceneLayout = SceneLayout.presetLayout(preset, for: .vertical)
            let result = CameraZoomMotion.scene(.init(scene: scene,
                zoom: .init(amount: 0.5, position: .zero), intensity: 2))
            XCTAssertEqual(result, scene)
        }
    }

    func testFullDisplayZoomStartsAtFitAndKeepsCursorTargetAnchored() {
        var placement = VideoRenderPlacement(kind: .screen,
            targetRect: CGRect(x: 100, y: 100, width: 800, height: 600), contentMode: .aspectFit)
        let original = placement.sourceFrame(sourceAspectRatio: 16.0 / 9)
        XCTAssertEqual(original, CGRect(x: 100, y: 175, width: 800, height: 450))
        placement.sourceCropAmount = CGPoint(x: 0.5, y: 0.5)
        placement.sourceCropPosition = CGPoint(x: -1, y: -1)
        let zoomed = placement.sourceFrame(sourceAspectRatio: 16.0 / 9)
        XCTAssertEqual(zoomed.size, CGSize(width: 1600, height: 900))
        XCTAssertEqual(zoomed.origin, original.origin)
        placement.sourceCropAmount = .zero
        XCTAssertEqual(placement.sourceFrame(sourceAspectRatio: 16.0 / 9), original)
    }
}
