import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class CameraFramingRegressionTests: XCTestCase {
    func testResetLayoutRestoresPortraitCameraFromPersistedFit() throws {
        let suite = "CameraFramingRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let studio = RecorderStudioConfiguration(defaults: defaults)
        studio.settings.layout = .horizontal
        studio.applyScenePreset(.webcamLeft)
        studio.setCameraContentMode(.fit)

        studio.resetSceneLayout()

        let restored = RecorderStudioConfiguration(defaults: defaults).settings
        XCTAssertEqual(studio.settings.cameraContentMode, .fill)
        XCTAssertEqual(restored.cameraContentMode, .fill)
        let view = makeFitPreview()
        view.sceneLayout = restored.sceneLayout
        view.cameraContentMode = restored.cameraContentMode
        view.layoutSubtreeIfNeeded()
        let frame = view.renderedCameraFrameForTesting
        XCTAssertGreaterThan(frame.height, frame.width)
        XCTAssertEqual(frame.height, view.canvasFrame.height, accuracy: 0.001)
    }

    func testCropFromFitFillsSideBySideSlotAndPersistsAcrossCameraToggleAndReload() throws {
        let suite = "CameraFramingRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let studio = RecorderStudioConfiguration(defaults: defaults)
        studio.settings.layout = .horizontal
        studio.applyScenePreset(.webcamLeft)
        studio.setCameraContentMode(.fit)
        let slot = studio.settings.sceneLayout.cameraFrame
        let control = CameraCropControl(amount: CGPoint(x: 0.3, y: 0.3), position: CGPoint(x: 0.4, y: 0))
        var updates = 0
        studio.updateRecordingScene = { _ in updates += 1 }

        studio.setCameraCrop(control)

        XCTAssertEqual(updates, 1)
        XCTAssertEqual(studio.settings.cameraContentMode, .fill)
        XCTAssertEqual(studio.settings.sceneLayout.cameraFrame, slot)
        studio.removeSource(.camera)
        studio.addSource(.camera)
        let restored = RecorderStudioConfiguration(defaults: defaults).settings
        XCTAssertEqual(restored.cameraContentMode, .fill)
        XCTAssertEqual(restored.cameraCropAmount, control.amount)
        XCTAssertEqual(restored.cameraCropPosition, control.position)
        XCTAssertEqual(restored.sceneLayout.cameraFrame, slot)
        XCTAssertTrue(restored.visibleSources.contains(.camera))

        let render = SceneRenderGeometry(
            canvas: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scene: RecordingScene(settings: restored),
            origin: .upperLeft
        )
        let placement = render.videoPlacement(for: .camera)
        let size = CGSize(width: 1920, height: 1080)
        let crop = try XCTUnwrap(placement.cropRectangle(naturalSize: size))
        let transformed = crop.applying(placement.transform(naturalSize: size, preferredTransform: .identity))
        XCTAssertEqual(transformed.width, placement.targetRect.width, accuracy: 0.001)
        XCTAssertEqual(transformed.height, placement.targetRect.height, accuracy: 0.001)
        XCTAssertEqual(transformed.midX, placement.targetRect.midX, accuracy: 0.001)
        XCTAssertEqual(transformed.midY, placement.targetRect.midY, accuracy: 0.001)
    }

    func testCameraPresetsRestoreFillAfterFitAndDisabledCamera() {
        for layout in CaptureLayout.allCases {
            for preset in ScenePreset.allCases where preset.supports(layout) && preset.requiredVideoSources.contains(.camera) {
                var settings = RecordingSettings()
                settings.layout = layout
                settings.enabledSources = [.screen, .microphone]
                settings.cameraContentMode = .fit
                let applied = RecordingSceneMutation.applyingPreset(
                    preset,
                    to: settings,
                    screenAspectRatio: 16.0 / 9.0,
                    cameraAspectRatio: 16.0 / 9.0
                )
                XCTAssertEqual(applied.cameraContentMode, .fill, "\(layout) \(preset)")
                XCTAssertTrue(applied.visibleSources.contains(.camera))
                XCTAssertTrue(applied.enabledSources.contains(.microphone))
            }
        }
    }

    func testCameraTogglePreservesDeliberateFitAndCustomPlacement() {
        let studio = RecorderStudioConfiguration(defaults: nil)
        studio.settings.cameraContentMode = .fit
        let original = studio.settings.sceneLayout

        studio.removeSource(.camera)
        studio.addSource(.camera)

        XCTAssertEqual(studio.settings.cameraContentMode, .fit)
        XCTAssertEqual(studio.settings.sceneLayout, original)
    }

    func testCropCommitFromFitExpandsVisibleCameraWithoutResizingLayout() throws {
        let view = makeFitPreview()
        let originalLayout = view.sceneLayout
        let originalVisibleFrame = view.renderedCameraFrameForTesting
        var committed: CameraCropControl?
        view.onCameraCropChanged = { committed = $0 }
        view.beginCameraCropEditing()
        view.updateCameraCropDraft(amount: CGPoint(x: 0.25, y: 0.25), position: CGPoint(x: 0.4, y: 0))

        view.commitCameraCropEditing()
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.cameraContentMode, .fill)
        XCTAssertEqual(view.sceneLayout, originalLayout)
        XCTAssertGreaterThan(view.renderedCameraFrameForTesting.height, originalVisibleFrame.height)
        XCTAssertEqual(try XCTUnwrap(committed).amount, CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(committed?.position, CGPoint(x: 0.4, y: 0))
    }

    func testCancellingCropFromFitPreservesFramingAndCrop() {
        let view = makeFitPreview()
        let originalFrame = view.renderedCameraFrameForTesting
        var commits = 0
        view.onCameraCropChanged = { _ in commits += 1 }
        view.beginCameraCropEditing()
        view.updateCameraCropDraft(amount: CGPoint(x: 0.4, y: 0.4), position: CGPoint(x: -0.5, y: 0))

        view.cancelCameraCropEditing()
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(commits, 0)
        XCTAssertEqual(view.cameraContentMode, .fit)
        XCTAssertEqual(view.cameraCropAmount, .zero)
        XCTAssertEqual(view.cameraCropPosition, .zero)
        XCTAssertEqual(view.renderedCameraFrameForTesting, originalFrame)
    }

    func testEditorCropCommitIncludesFramingAndLeavesOriginalAvailableForUndo() throws {
        var settings = RecordingSettings()
        settings.layout = .horizontal
        settings.cameraContentMode = .fit
        settings.sceneLayout = SceneLayout.presetLayout(.webcamLeft, for: .horizontal)
        let original = RecordingScene(settings: settings)
        var draft = try XCTUnwrap(EditorCameraCropSession.begin(
            eventIndex: 0,
            sceneEvents: [RecordingSceneEvent(time: 0, scene: original)]
        ))
        draft.scene.cameraCropAmount = CGPoint(x: 0.2, y: 0.2)
        draft.scene.cameraCropPosition = CGPoint(x: -0.3, y: 0)
        let commit = EditorCameraCropSession.commit(draft)
        var result = original

        commit.apply(to: &result)

        XCTAssertEqual(result.cameraContentMode, .fill)
        XCTAssertEqual(result.cameraCropAmount, draft.scene.cameraCropAmount)
        XCTAssertEqual(result.cameraCropPosition, draft.scene.cameraCropPosition)
        XCTAssertEqual(result.sceneLayout, original.sceneLayout)
        XCTAssertEqual(draft.originalScene, original)
        XCTAssertEqual(draft.originalScene.cameraContentMode, .fit)
    }

    private func makeFitPreview() -> PreviewStageView {
        let view = PreviewStageView()
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        view.captureLayout = .horizontal
        view.enabledSources = [.screen, .camera]
        view.sceneLayout = SceneLayout.presetLayout(.webcamLeft, for: .horizontal)
        view.cameraContentMode = .fit
        view.selectedLayer = .camera
        view.layoutSubtreeIfNeeded()
        return view
    }
}
