import CoreGraphics
import XCTest
@testable import BlitzRecorderApp

final class MulticamProgramTests: XCTestCase {
    private let angles = [
        CameraAngleRecord(role: "camera", title: "wide-shot", offsetSeconds: 0, method: .audio, confidence: 1, drift: 0,
                          face: nil, faceCount: 2, aspectRatio: 16.0 / 9.0),
        CameraAngleRecord(role: "camera-2", title: "plan-emmanuel", offsetSeconds: 18.1, method: .reference,
                          confidence: 1, drift: 0, face: CGRect(x: 0.47, y: 0.33, width: 0.08, height: 0.15),
                          faceCount: 1, aspectRatio: 16.0 / 9.0),
        CameraAngleRecord(role: "camera-3", title: "plan-thomas", offsetSeconds: 72.36, method: .audio, confidence: 1,
                          drift: 0, face: CGRect(x: 0.45, y: 0.26, width: 0.08, height: 0.15), faceCount: 1,
                          aspectRatio: 16.0 / 9.0)
    ]

    private func scene(_ shot: MulticamShot) -> RecordingScene {
        var scene = RecordingScene(settings: RecordingSettings())
        shot.apply(to: &scene, .init(angles: angles, canvas: .horizontal, framing: .standard(for: shot)))
        return scene
    }

    /// Wide until 1:12, the speakers side by side until 10:00, Thomas alone until 11:40, then side by side again.
    private func program(soundRole: String?) throws -> MulticamProgram {
        let sideBySide = MulticamShot.sideBySide(left: "camera-2", right: "camera-3")
        return try XCTUnwrap(MulticamProgram(.init(
            angles: angles, soundRole: soundRole,
            sceneEvents: [
                .init(time: 0, scene: scene(.camera(role: "camera"))),
                .init(time: 72, scene: scene(sideBySide)),
                .init(time: 600, scene: scene(.camera(role: "camera-3"))),
                .init(time: 700, scene: scene(sideBySide))
            ],
            duration: 1800, canvas: .horizontal
        )))
    }

    func testEachCameraKnowsWhereItIsOnScreen() throws {
        let program = try program(soundRole: "camera-2")
        XCTAssertEqual(program.angle(role: "camera")?.liveRanges, [0..<72])
        XCTAssertEqual(program.angle(role: "camera-2")?.liveRanges, [72..<600, 700..<1800])
        XCTAssertEqual(program.angle(role: "camera-3")?.liveRanges, [72..<1800], "touching parts read as one stretch")
        XCTAssertEqual(program.angle(role: "camera-3")?.isLive(at: 650), true)
        XCTAssertEqual(program.angle(role: "camera-2")?.isLive(at: 650), false)
    }

    func testShotsAndTilesFollowThePlayhead() throws {
        let program = try program(soundRole: nil)
        XCTAssertEqual(program.shots.map(\.key), [1, 2, 3, 4])
        XCTAssertEqual(program.shots.map(\.title), ["wide-shot", "plan-emmanuel", "plan-thomas", "Side by side"])
        XCTAssertEqual(program.angles.map(\.key), [1, 2, 3], "a camera's key cuts to that camera alone")
        XCTAssertEqual(program.shot(key: 3), .camera(role: "camera-3"))
        XCTAssertNil(program.shot(key: 9))
        XCTAssertEqual(program.liveShot(at: 10), .camera(role: "camera"))
        XCTAssertEqual(program.liveShot(at: 300), .sideBySide(left: "camera-2", right: "camera-3"))
        XCTAssertEqual(program.tiles(at: 300), .init(left: "camera-2", right: "camera-3"))
        XCTAssertNil(program.tiles(at: 650), "one camera fills the canvas")
    }

    func testOneCameraPlaysTheSound() throws {
        XCTAssertEqual(try program(soundRole: nil).angles.filter(\.isSound).map(\.role), ["camera"],
                       "Camera 1 plays until another camera's sound is picked")
        XCTAssertEqual(try program(soundRole: "camera-3").angles.filter(\.isSound).map(\.role), ["camera-3"])
    }

    func testCutsKeepTheSpeakersAsCloseAsTheyAre() throws {
        let program = try program(soundRole: nil)
        let thomas = MulticamShot.camera(role: "camera-3")
        XCTAssertEqual(program.liveFraming(at: 300), .standard(for: .sideBySide(left: "camera-2", right: "camera-3")))
        XCTAssertEqual(program.framing(cuttingTo: thomas, at: 300).closeness, .medium, "side by side is head and shoulders")
        XCTAssertEqual(program.framing(cuttingTo: thomas, at: 10), .standard(for: thomas), "the wide shot has no closeness")

        var close = RecordingScene(settings: RecordingSettings())
        let sideBySide = MulticamShot.sideBySide(left: "camera-2", right: "camera-3")
        sideBySide.apply(to: &close, .init(angles: angles, canvas: .horizontal,
                                           framing: .init(closeness: .close, spacing: .large)))
        XCTAssertEqual(sideBySide.framing(of: close, .init(angles: angles, canvas: .horizontal)),
                       .init(closeness: .close, spacing: .large))
        XCTAssertGreaterThan(close.cameraCropAmount.x, scene(sideBySide).cameraCropAmount.x, "close crops further in")
    }

    func testARecordedTakeIsNotMulticam() {
        XCTAssertNil(MulticamProgram(.init(angles: Array(angles.prefix(1)), soundRole: nil, sceneEvents: [], duration: 60, canvas: .horizontal)))
    }
}
