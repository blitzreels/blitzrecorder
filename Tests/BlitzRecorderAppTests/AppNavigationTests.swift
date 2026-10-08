import AppKit
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class AppNavigationTests: XCTestCase {
    func testReturningToTheSameProjectPreservesEditsAndUndoHistory() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let vm = fixture.vm
        vm.openProject(fixture.entry)
        let original = try XCTUnwrap(vm.lastExportedProject)
        let edits = try XCTUnwrap(EditorTimeRange.removing(.init(
            range: .init(start: 2, end: 4), edits: original.edits, takeDuration: 10)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: edits, actionName: "Cut Range")))
        var menuUndoAvailability: [Bool] = []
        vm.onEditorHistoryChanged = { [weak vm] in menuUndoAvailability.append(vm?.canUndoEditor ?? false) }
        let scene = vm.selectedSceneID
        let settings = vm.settings.sceneLayout
        vm.showProjects()
        XCTAssertFalse(vm.isEditorVisible)
        vm.showSettings(.devices)
        XCTAssertTrue(vm.isShowingSettings)
        vm.showRecorder()
        XCTAssertFalse(vm.isShowingSettings)
        XCTAssertEqual(vm.selectedSceneID, scene)
        XCTAssertEqual(vm.settings.sceneLayout, settings)
        vm.openProject(fixture.entry)
        XCTAssertTrue(vm.isEditorVisible)
        XCTAssertTrue(vm.canUndoEditor)
        XCTAssertTrue(menuUndoAvailability.contains(false))
        XCTAssertEqual(menuUndoAvailability.last, true)
        XCTAssertEqual(vm.editorUndoTitle, "Undo Cut Range")
        XCTAssertEqual(vm.lastExportedProject?.edits, edits)
        vm.undoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, original.edits)
        XCTAssertTrue(vm.canRedoEditor)
    }

    func testSidebarDestinationsRoundTripBetweenEditorAndLibrary() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let vm = fixture.vm
        vm.openProject(fixture.entry)
        let projectID = try XCTUnwrap(vm.lastExportedProject?.id)
        XCTAssertEqual(vm.sidebarDestination, .editor)

        vm.showSidebarDestination(.shared)
        XCTAssertEqual(vm.studioMode, .projects)
        XCTAssertEqual(vm.sidebarDestination, .shared)

        let folder = try XCTUnwrap(ProjectFolderPath(["Formation IA"]))
        vm.showSidebarDestination(.folder(.init(path: folder, module: nil)))
        XCTAssertEqual(vm.projectLibraryNavigation.section, .recordings)
        XCTAssertEqual(vm.sidebarDestination, .folder(.init(path: folder, module: nil)))

        vm.showSidebarDestination(.settings)
        XCTAssertEqual(vm.sidebarDestination, .settings)
        vm.showSidebarDestination(.recordings)
        XCTAssertFalse(vm.isShowingSettings)
        XCTAssertNil(vm.projectLibraryNavigation.folderScope)
        XCTAssertEqual(vm.sidebarDestination, .recordings)

        vm.showSidebarDestination(.editor)
        XCTAssertTrue(vm.isEditorVisible)
        XCTAssertEqual(vm.lastExportedProject?.id, projectID)

        vm.showSidebarDestination(.record)
        XCTAssertEqual(vm.sidebarDestination, .record)
    }

    func testBrowsingPagesDuringCaptureKeepsItsStateAndBlocksOpeningAnotherTake() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        for state in [RecordingState.starting, .recording, .paused, .finishing] {
            fixture.vm.applyState(state)
            let settings = fixture.vm.settings.sceneLayout
            fixture.vm.showProjects()
            XCTAssertEqual(fixture.vm.studioMode, .projects)
            XCTAssertEqual(fixture.vm.state, state)
            fixture.vm.openProject(fixture.entry)
            XCTAssertEqual(fixture.vm.studioMode, .projects)
            XCTAssertNil(fixture.vm.lastExportedProject)
            fixture.vm.showSettings(.permissions)
            XCTAssertEqual(fixture.vm.state, state)
            fixture.vm.showRecorder()
            XCTAssertEqual(fixture.vm.state, state)
            XCTAssertEqual(fixture.vm.settings.sceneLayout, settings)
        }
        fixture.vm.applyState(.idle)
    }

    func testHiddenEditorDoesNotConsumeProjectOrRecorderShortcuts() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let editor = EditorView(vm: fixture.vm)
        for key in [("\r", UInt16(36)), (" ", UInt16(49)), ("\u{7f}", UInt16(51))] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: key.0, charactersIgnoringModifiers: key.0, isARepeat: false, keyCode: key.1))
            fixture.vm.showProjects()
            XCTAssertFalse(editor.handleKeyboardShortcut(event))
            fixture.vm.showRecorder()
            XCTAssertFalse(editor.handleKeyboardShortcut(event))
            fixture.vm.showSettings(nil)
            XCTAssertFalse(editor.handleKeyboardShortcut(event))
        }
    }

    @MainActor
    private struct Fixture {
        let vm: RecorderViewModel
        let entry: RecordingProjectHistory.Entry
        let defaults: UserDefaults
        let suite: String
        let directory: URL

        init() throws {
            suite = "AppNavigationTests.\(UUID().uuidString)"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            var settings = RecordingSettings()
            settings.outputDirectory = directory
            settings.enabledSources = [.screen]
            RecordingSettingsStore.save(settings, defaults: defaults)
            let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
            vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
            let store = TakeFileStore()
            let take = try store.createTake(settings: settings)
            try Data().write(to: take.screenURL)
            entry = try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first)
        }

        func cleanup() {
            vm.elapsedClock.applyState(.idle, previousState: vm.state)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

extension AppNavigationTests {
    func testExportCompletionDoesNotChangePageOrInterruptANewRecording() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let vm = fixture.vm
        vm.applyExportProject(URL(fileURLWithPath: fixture.entry.projectPath))
        vm.exportProgress = 0.6
        vm.applyState(.recording)
        XCTAssertEqual(vm.exportProgress, 0.6)
        vm.showProjects()
        vm.applySavedRecordingOutput(.init(url: fixture.directory.appendingPathComponent("export.mp4"),
            sourceDirectory: URL(fileURLWithPath: fixture.entry.takeDirectoryPath), warning: nil))
        vm.applyExportProject(nil)
        XCTAssertEqual(vm.studioMode, .projects)
        XCTAssertEqual(vm.state, .recording)
        XCTAssertNotNil(vm.lastExportSucceededURL)
        XCTAssertFalse(vm.isExporting)
        vm.applyState(.idle)
    }

    func testFinishingAnExportDoesNotChangeRecordingPreparationState() {
        let session = RecordingSession()
        XCTAssertTrue(session.beginExport())
        XCTAssertTrue(session.beginPreparation(.init(outputDirectoryAccess: OutputDirectoryAccess(
            url: FileManager.default.temporaryDirectory, usesSecurityScopedBookmark: false))))
        XCTAssertEqual(session.state, .starting)
        session.finishExport()
        XCTAssertEqual(session.state, .starting)
        XCTAssertFalse(session.isExporting)
        XCTAssertTrue(session.beginExport())
        XCTAssertEqual(session.state, .starting)
        session.finishExport()
        session.failPreparation()
    }
}
