import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class EditorWindowSessionTests: XCTestCase {
    func testCaptureRuntimeAllowsSavedProjectEditsAndUndoButProtectsTheActiveTake() throws {
        let fixture = try fixture()
        let settings = fixture.recorder.settings
        let runtime = RecorderCaptureRuntime(
            studio: fixture.recorder.coordinator.studio,
            permissionGate: fixture.recorder.coordinator.permissionGate,
            recents: .init(defaults: fixture.defaults)
        )
        let store = TakeFileStore()
        let projectURL = URL(fileURLWithPath: fixture.project.projectPath)
        let original = try store.loadRecordingProject(at: projectURL)
        let activeTake = try store.createTake(settings: settings)
        let activeOriginal = try store.loadRecordingProject(at: activeTake.projectURL)
        let state = RecordingProject.EditorStateSnapshot(
            hiddenVideoSources: ["camera"], mutedAudioSources: ["microphone"], backgroundMusicPath: nil,
            backgroundMusicBookmarkData: nil, backgroundMusicVolume: nil, exportRecipe: nil
        )
        XCTAssertTrue(runtime.recordingSession.beginPreparation(.init(
            outputDirectoryAccess: OutputDirectoryAccess(url: settings.outputDirectory, usesSecurityScopedBookmark: false)
        )))
        runtime.recordingSession.noteActiveTake(.init(take: activeTake, settings: settings))
        for expected in [RecordingState.starting, .recording, .paused, .finishing] {
            switch expected {
            case .recording: runtime.recordingSession.markRecordingStarted()
            case .paused: XCTAssertTrue(runtime.recordingSession.pause())
            case .finishing: XCTAssertNotNil(runtime.recordingSession.beginFinishing())
            default: break
            }
            XCTAssertEqual(runtime.state, expected)
            let updated = try runtime.updateProjectEditorState(.init(
                projectURL: projectURL, editorState: state, baseSettings: settings
            ))
            XCTAssertEqual(updated.editorState, state)
            let sceneEdit = try runtime.updateProjectScene(at: projectURL, eventIndex: 0) {
                $0.canvasPadding = 0.05
            }
            XCTAssertNotEqual(sceneEdit.sceneEvents, original.sceneEvents)
            let restored = try runtime.restoreProjectSceneTimeline(.init(
                projectURL: projectURL, snapshot: original, baseSettings: settings
            ))
            XCTAssertEqual(restored.editorState, original.editorState)
            XCTAssertThrowsError(try runtime.updateProjectEditorState(.init(
                projectURL: activeTake.projectURL, editorState: state, baseSettings: settings
            )))
            XCTAssertThrowsError(try runtime.restoreProjectSceneTimeline(.init(
                projectURL: activeTake.projectURL, snapshot: original, baseSettings: settings
            )))
            XCTAssertEqual(try store.loadRecordingProject(at: activeTake.projectURL), activeOriginal)
            XCTAssertEqual(runtime.state, expected)
        }
        runtime.recordingSession.finish(with: activeTake)
    }

    func testEditorProjectAndUndoSurviveRecordingStartAndFinalization() throws {
        let fixture = try fixture()
        let recorder = fixture.recorder
        let editor = RecorderViewModel(coordinator: recorder.coordinator, previewStage: PreviewStageView())
        editor.settings = recorder.settings
        editor.openProject(fixture.project)
        let original = try XCTUnwrap(editor.lastExportedProject)
        let state = RecordingProject.EditorStateSnapshot(
            hiddenVideoSources: [], mutedAudioSources: ["microphone"], backgroundMusicPath: nil,
            backgroundMusicBookmarkData: nil, backgroundMusicVolume: nil, exportRecipe: nil
        )
        XCTAssertTrue(editor.applyProjectEditorState(.init(editorState: state, actionName: "Mute Microphone")))
        let edited = editor.lastExportedProject

        for captureState in [RecordingState.starting, .recording, .paused, .finishing, .idle] {
            recorder.applyState(captureState)
            XCTAssertEqual(editor.state, .idle)
            XCTAssertTrue(editor.isEditorVisible)
            XCTAssertEqual(editor.lastExportedProject, edited)
            XCTAssertTrue(editor.canUndoEditor)
        }
        let take = try TakeFileStore().createTake(settings: recorder.settings)
        recorder.applyPostRecordingProjectOutput(.init(
            projectURL: take.projectURL, sourceDirectory: take.scratchDirectory, warning: nil
        ))
        XCTAssertEqual(editor.lastExportedProject?.id, original.id)
        editor.undoEditor()
        XCTAssertEqual(editor.lastExportedProject?.editorState, original.editorState)
        editor.redoEditor()
        XCTAssertEqual(editor.lastExportedProject?.editorState, state)
        let reopened = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: original.projectPath))
        XCTAssertEqual(reopened.editorState, state)
    }

    func testRecordingRoutesProjectToEditorWindowWithoutChangingCaptureView() throws {
        let fixture = try fixture()
        let recorder = fixture.recorder
        recorder.applyState(.starting)
        recorder.applyState(.recording)
        var opened: RecordingProjectHistory.Entry?
        recorder.onRouteEditorProject = { opened = $0; return true }
        XCTAssertTrue(recorder.canOpenProjectEditor)
        recorder.openProject(fixture.project)
        XCTAssertEqual(opened?.id, fixture.project.id)
        XCTAssertEqual(recorder.state, .recording)
        XCTAssertEqual(recorder.studioMode, .record)
        XCTAssertNil(recorder.lastExportedProject)
    }

    func testMovingEditorHistoryLeavesOnlyOneUndoOwnerAndRoutesExport() throws {
        let fixture = try fixture()
        let recorder = fixture.recorder
        recorder.openProject(fixture.project)
        let state = RecordingProject.EditorStateSnapshot(
            hiddenVideoSources: ["camera"], mutedAudioSources: [], backgroundMusicPath: nil,
            backgroundMusicBookmarkData: nil, backgroundMusicVolume: nil, exportRecipe: nil
        )
        XCTAssertTrue(recorder.applyProjectEditorState(.init(editorState: state, actionName: "Hide Camera")))
        let editor = RecorderViewModel(coordinator: recorder.coordinator, previewStage: PreviewStageView())
        editor.settings = recorder.settings
        editor.openProject(fixture.project)
        recorder.moveEditorHistory(to: editor)
        XCTAssertFalse(recorder.canUndoEditor)
        XCTAssertTrue(editor.canUndoEditor)
        editor.undoEditor()
        XCTAssertEqual(editor.lastExportedProject?.editorState.hiddenVideoSources, [])

        recorder.hasSeparateEditorWindow = true
        var request: EditorWindowRequest?
        recorder.onOpenEditorWindow = { request = $0 }
        recorder.showRecorder()
        recorder.openEditorForExport()
        XCTAssertEqual(request?.project?.id, fixture.project.id)
        XCTAssertEqual(request?.presentsExport, true)
        XCTAssertFalse(recorder.isEditorExportPresented)
        XCTAssertEqual(recorder.studioMode, .record)
        recorder.openEditorWindow()
        XCTAssertNil(request?.project)
        XCTAssertEqual(request?.presentsExport, false)
    }

    func testEditorInitializationAndRecorderNavigationDoNotReplaceCaptureCallbacks() throws {
        let fixture = try fixture()
        var messages: [String] = []
        fixture.recorder.coordinator.onScreenWindowFitMessage = { messages.append($0) }
        let editor = RecorderViewModel(coordinator: fixture.recorder.coordinator, previewStage: PreviewStageView())
        fixture.recorder.coordinator.onScreenWindowFitMessage?("Fitted")
        XCTAssertEqual(messages, ["Fitted"])
        var requests = 0
        editor.studioMode = .edit
        editor.onShowRecorder = { requests += 1 }
        editor.showRecorder()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(editor.isEditorVisible)
    }

    private struct Fixture {
        let recorder: RecorderViewModel
        let project: RecordingProjectHistory.Entry
        let defaults: UserDefaults
    }

    private func fixture() throws -> Fixture {
        let name = "EditorWindowSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        var settings = RecordingSettings()
        settings.outputDirectory = directory
        settings.savesSourceFiles = true
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let recorder = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        _ = try TakeFileStore().createTake(settings: settings)
        recorder.refreshRecentProjects()
        return Fixture(recorder: recorder, project: try XCTUnwrap(recorder.recentProjects.first), defaults: defaults)
    }
}
