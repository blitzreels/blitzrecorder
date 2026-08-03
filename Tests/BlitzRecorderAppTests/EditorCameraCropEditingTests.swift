import CoreGraphics
import XCTest
@testable import BlitzRecorderApp

final class EditorCameraCropEditingTests: XCTestCase {
    func testProjectPersistsCameraCropAmountAndPositionAfterReopen() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorCameraCropEditingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: outputDirectory)
        }
        var settings = RecordingSettings()
        settings.outputDirectory = outputDirectory
        settings.enabledSources = [.camera]

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try Data().write(to: take.cameraURL)
        _ = try store.updateProjectScene(
            at: take.projectURL,
            eventIndex: 0,
            baseSettings: settings
        ) { scene in
            scene.cameraCropAmount = CGPoint(x: 0.42, y: 0.42)
            scene.cameraCropPosition = CGPoint(x: 0.65, y: -0.3)
        }

        let reloadedProject = try store.loadRecordingProject(at: take.projectURL)
        let reloadedScene = try XCTUnwrap(store.sceneEvents(from: reloadedProject).first?.scene)
        XCTAssertEqual(reloadedScene.cameraCropAmount, CGPoint(x: 0.42, y: 0.42))
        XCTAssertEqual(reloadedScene.cameraCropPosition, CGPoint(x: 0.65, y: -0.3))
    }

    func testPresentationShrinksCanvasToRevealFullLandscapeCameraDuringVerticalCropEditing() throws {
        var settings = RecordingSettings()
        settings.layout = .vertical
        settings.enabledSources = [.camera]
        settings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .vertical)
        let scene = RecordingScene(settings: settings)

        let presentation = try XCTUnwrap(EditorCameraCropPresentation.make(.init(
            containerSize: CGSize(width: 900, height: 1_600),
            renderSize: CGSize(width: 1_080, height: 1_920),
            scene: scene,
            sourceAspectRatio: 16.0 / 9.0
        )))

        XCTAssertGreaterThanOrEqual(presentation.sourceFrame.minX, 0)
        XCTAssertLessThanOrEqual(presentation.sourceFrame.maxX, 900.0001)
        XCTAssertGreaterThanOrEqual(presentation.sourceFrame.minY, 0)
        XCTAssertLessThanOrEqual(presentation.sourceFrame.maxY, 1_600.0001)
        XCTAssertLessThan(presentation.canvasFrame.width, 900)
        XCTAssertEqual(presentation.cropFrame, presentation.canvasFrame)
    }

    func testPresentationMapsSavedCropPositionInsideVisibleSource() throws {
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.enabledSources = [.camera]
        settings.sceneLayout = SceneLayout.presetLayout(.webcamFullscreen, for: .horizontal)
        settings.cameraCropAmount = CGPoint(x: 0.35, y: 0.35)
        settings.cameraCropPosition = CGPoint(x: 0.7, y: -0.4)
        let scene = RecordingScene(settings: settings)

        let presentation = try XCTUnwrap(EditorCameraCropPresentation.make(.init(
            containerSize: CGSize(width: 1_200, height: 675),
            renderSize: CGSize(width: 1_920, height: 1_080),
            scene: scene,
            sourceAspectRatio: 4.0 / 3.0
        )))

        XCTAssertTrue(presentation.sourceFrame.contains(presentation.cropFrame))
        XCTAssertLessThan(presentation.cropFrame.width, presentation.sourceFrame.width)
        XCTAssertGreaterThan(presentation.cropFrame.midX, presentation.sourceFrame.midX)
        XCTAssertLessThan(presentation.cropFrame.midY, presentation.sourceFrame.midY)
    }
}
