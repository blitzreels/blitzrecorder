import CoreGraphics
@testable import BlitzRecorderApp
import XCTest

final class RecordingSceneTests: XCTestCase {
    func testRecordingSceneCapturesRenderState() {
        var settings = RecordingSettings()
        settings.outputResolution = .p720
        settings.outputVideoFormat = .mp4
        settings.framesPerSecond = 24
        settings.sceneLayout = SceneLayout.presetLayout(.cameraInset, for: .horizontal)
        settings.enabledSources = [.screen, .camera, .microphone]
        settings.hiddenSources = [.camera]
        settings.usesPickedScreenContent = true
        settings.selectedDisplayID = "42"
        settings.screenCrop = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        settings.cameraCropAmount = CGPoint(x: 0.2, y: 0.1)
        settings.cameraCropPosition = CGPoint(x: -0.3, y: 0.4)
        settings.canvasBackgroundStyle = .ocean
        settings.canvasBackgroundAnimated = true
        settings.canvasPadding = 0.08

        let scene = RecordingScene(settings: settings)

        XCTAssertEqual(scene.enabledSources, [.screen, .microphone])
        XCTAssertEqual(scene.sceneLayout, SceneLayout.presetLayout(.cameraInset, for: .horizontal))
        XCTAssertEqual(scene.screenSourceGeometry.usesPickedContent, true)
        XCTAssertEqual(scene.screenSourceGeometry.selectedDisplayID, "42")
        XCTAssertEqual(scene.screenSourceGeometry.normalizedCrop, CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5))
        XCTAssertEqual(scene.cameraCropAmount, CGPoint(x: 0.2, y: 0.1))
        XCTAssertEqual(scene.cameraCropPosition, CGPoint(x: -0.3, y: 0.4))
        XCTAssertEqual(scene.canvasBackgroundStyle, .ocean)
        XCTAssertEqual(scene.canvasBackgroundAnimated, true)
        XCTAssertEqual(scene.canvasPadding, 0.08)
    }
}
