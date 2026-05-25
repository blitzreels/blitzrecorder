import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class RecordingSceneTests: XCTestCase {
    func testRecordingSceneCapturesOnlyLiveCompositionState() {
        var settings = RecordingSettings()
        settings.outputResolution = .p720
        settings.outputVideoFormat = .mp4
        settings.framesPerSecond = 24
        settings.sceneLayout = SceneLayout.presetLayout(.cameraInset, for: .horizontal)
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.cameraCropAmount = CGPoint(x: 0.2, y: 0.1)
        settings.cameraCropPosition = CGPoint(x: -0.3, y: 0.4)
        settings.canvasBackgroundStyle = .ocean
        settings.canvasPadding = 0.08

        let scene = RecordingScene(settings: settings)

        XCTAssertEqual(scene.enabledSources, [.screen, .camera, .microphone])
        XCTAssertEqual(scene.sceneLayout, SceneLayout.presetLayout(.cameraInset, for: .horizontal))
        XCTAssertEqual(scene.cameraCropAmount, CGPoint(x: 0.2, y: 0.1))
        XCTAssertEqual(scene.cameraCropPosition, CGPoint(x: -0.3, y: 0.4))
        XCTAssertEqual(scene.canvasBackgroundStyle, .ocean)
        XCTAssertEqual(scene.canvasPadding, 0.08)
    }
}
