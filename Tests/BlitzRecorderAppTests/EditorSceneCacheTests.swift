import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class EditorSceneCacheTests: XCTestCase {
    func testTextLayersReusePixelsAndRefreshAfterEditsAndSeeking() async throws {
        _ = NSApplication.shared
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let store = TakeFileStore()
        var edits = TimelineEdits.empty
        edits.textOverlays = [.init(start: 0, end: 1, text: "First title",
                                   frame: TextOverlay.defaultFrame(for: .title), style: .title, fadeSeconds: 0)]
        var project = try store.updateProjectTimelineEdits(.init(
            projectURL: fixture.take.projectURL, edits: edits, baseSettings: fixture.settings))
        let controller = EditorPlaybackController()
        let view = EditorCompositedPlayerView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        defer { view.teardown(); controller.teardown() }
        await controller.load(project: project, baseSettings: fixture.settings)
        view.controller = controller
        view.configure(renderSize: CGSize(width: 1280, height: 720))
        view.refresh()
        let canvas = try XCTUnwrap(view.layer?.sublayers?.first)
        let title = try XCTUnwrap(canvas.sublayers?.first { $0.zPosition == 100 })
        let image = try XCTUnwrap(title.contents as AnyObject?)
        view.refresh()
        XCTAssertTrue(image === title.contents as AnyObject?)
        edits.textOverlays[0].text = "Changed title"
        project = try store.updateProjectTimelineEdits(.init(
            projectURL: fixture.take.projectURL, edits: edits, baseSettings: fixture.settings))
        XCTAssertTrue(controller.refreshSceneTimeline(.init(project: project, baseSettings: fixture.settings,
                                                            preservesPreviewSceneOverride: false)))
        view.refresh()
        XCTAssertFalse(image === title.contents as AnyObject?)
        controller.scrub(to: 2)
        view.refresh()
        XCTAssertFalse(canvas.sublayers?.contains { $0.zPosition == 100 } ?? false)
        controller.scrub(to: 0.5)
        view.refresh()
        XCTAssertTrue(canvas.sublayers?.contains { $0.zPosition == 100 } ?? false)
        view.teardown()
        XCTAssertFalse(canvas.sublayers?.contains { $0.zPosition == 100 } ?? false)
    }

    func testPreviewTracksVisibilityOverridesAndSavedSceneChanges() async throws {
        _ = NSApplication.shared
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        try FileManager.default.copyItem(at: fixture.take.screenURL, to: fixture.take.cameraURL)
        var settings = fixture.settings
        settings.enabledSources.insert(.camera)
        var first = RecordingScene(settings: settings)
        first.canvasPadding = 0.05
        var second = first
        second.canvasPadding = 0.1
        let store = TakeFileStore()
        try store.writeRecordingProject(for: fixture.take, settings: settings, sceneEvents: [
            .init(time: 0, scene: first), .init(time: 1, scene: second)
        ], finalVideoURL: nil)
        let project = try store.loadRecordingProject(at: fixture.take.projectURL)
        let controller = EditorPlaybackController()
        defer { controller.teardown() }
        await controller.load(project: project, baseSettings: settings)
        XCTAssertTrue(controller.isReady)
        let player = try XCTUnwrap(controller.videoPlayer(for: .screen))
        for _ in 0..<3 {
            controller.setHidden(true, kind: .camera)
            for time in [0.5, 1.5, 2.5] {
                XCTAssertFalse(try XCTUnwrap(controller.scene(at: time)).enabledSources.contains(.camera))
                XCTAssertFalse(controller.layerFrames(at: time).contains { $0.kind == .camera })
            }
            controller.setHidden(false, kind: .camera)
            XCTAssertTrue(try XCTUnwrap(controller.scene(at: 0.5)).enabledSources.contains(.camera))
            XCTAssertTrue(controller.layerFrames(at: 0.5).contains { $0.kind == .camera })
        }
        var override = first
        override.canvasPadding = 0.2
        controller.setPreviewSceneOverride(override, at: 0.5)
        XCTAssertEqual(controller.scene(at: 0.5)?.canvasPadding, 0.2)
        XCTAssertEqual(controller.scene(at: 1.5)?.canvasPadding, 0.1)
        controller.setPreviewSceneOverride(override, at: 1.5)
        XCTAssertEqual(controller.scene(at: 0.5)?.canvasPadding, 0.05)
        XCTAssertEqual(controller.scene(at: 1.5)?.canvasPadding, 0.2)
        controller.setPreviewSceneOverride(nil, at: 0)
        XCTAssertEqual(controller.scene(at: 1.5)?.canvasPadding, 0.1)

        let edited = try store.updateProjectScene(at: fixture.take.projectURL, eventIndex: 1,
                                                 baseSettings: settings) { $0.canvasPadding = 0.15 }
        XCTAssertTrue(controller.refreshSceneTimeline(.init(project: edited, baseSettings: settings,
                                                            preservesPreviewSceneOverride: false)))
        XCTAssertTrue(player === controller.videoPlayer(for: .screen))
        XCTAssertEqual(controller.scene(at: 1.5)?.canvasPadding, 0.15)
        controller.applyEditorState(.init(hiddenVideoSources: [SceneLayerKind.camera.rawValue], mutedAudioSources: [],
                                          backgroundMusicPath: nil, backgroundMusicBookmarkData: nil,
                                          backgroundMusicVolume: nil, exportRecipe: nil))
        XCTAssertFalse(try XCTUnwrap(controller.scene(at: 1.5)).enabledSources.contains(.camera))
        await controller.load(project: project, baseSettings: settings)
        XCTAssertEqual(controller.scene(at: 1.5)?.canvasPadding, 0.1)
        XCTAssertTrue(try XCTUnwrap(controller.scene(at: 1.5)).enabledSources.contains(.camera))
    }

    func testReplacingAnInFlightLoadPublishesOnlyTheLatestProject() async throws {
        _ = NSApplication.shared
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 90))
        let store = TakeFileStore()
        let initial = try store.loadRecordingProject(at: fixture.take.projectURL)
        let edited = try store.updateProjectScene(at: fixture.take.projectURL, eventIndex: 0,
                                                 baseSettings: fixture.settings) { $0.canvasPadding = 0.2 }
        let controller = EditorPlaybackController()
        defer { controller.teardown() }
        let firstLoad = Task { await controller.load(project: initial, baseSettings: fixture.settings) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while controller.videoPlayer(for: .screen) == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
        XCTAssertNotNil(controller.videoPlayer(for: .screen))
        controller.teardown()
        await controller.load(project: edited, baseSettings: fixture.settings)
        await firstLoad.value
        XCTAssertTrue(controller.isReady)
        XCTAssertNil(controller.loadError)
        XCTAssertEqual(controller.scene(at: 0.5)?.canvasPadding, 0.2)
        XCTAssertEqual(controller.scene(at: 0.8)?.canvasPadding, controller.scene(at: 0.5)?.canvasPadding)
    }

}
