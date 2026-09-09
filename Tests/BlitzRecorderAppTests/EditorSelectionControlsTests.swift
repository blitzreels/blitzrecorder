import AppKit
import CoreMedia
import XCTest

@testable import BlitzRecorderApp

final class EditorSelectionControlsTests: XCTestCase {
    func testDraggingBackwardsAndBeyondEdgesClampsToTake() throws {
        let range = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 14, head: -2, duration: 10)))
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 10)
        XCTAssertNil(EditorTimeRange.resolve(.init(anchor: .nan, head: 4, duration: 10)))
        XCTAssertNil(EditorTimeRange.resolve(.init(anchor: 1, head: .infinity, duration: 10)))
        XCTAssertNil(EditorTimeRange.resolve(.init(anchor: 1, head: 4, duration: 0)))
    }

    func testPointSelectionIsNotACut() throws {
        let range = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 5, head: 5, duration: 10)))
        XCTAssertFalse(range.canCut)
        XCTAssertNil(EditorTimeRange.removing(.init(range: range, edits: .empty, takeDuration: 10)))
    }

    func testRangeCutPreservesExistingEditsAndMergesOverlapInPlayback() throws {
        var original = TimelineEdits.empty
        original.cuts = [TimelineCut(start: 2, end: 4, kind: .silence, source: .automatic)]
        let range = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 3, head: 6, duration: 10)))
        let edited = try XCTUnwrap(EditorTimeRange.removing(.init(range: range, edits: original, takeDuration: 10)))
        XCTAssertEqual(edited.cuts.first, original.cuts.first)
        XCTAssertEqual(edited.cuts.last?.kind, .manual)
        XCTAssertEqual(edited.cuts.last?.source, .user)
        XCTAssertEqual(original.cuts.count, 1)
        let map = TimelineTimeMap(takeDuration: CMTime(seconds: 10, preferredTimescale: 600), cuts: edited.cuts)
        XCTAssertEqual(map.outputDuration.seconds, 6, accuracy: 0.001)
    }

    func testCannotRemoveAllRemainingFootageOrRepeatAnExistingCut() throws {
        var edits = TimelineEdits.empty
        edits.cuts = [TimelineCut(start: 0, end: 5, kind: .manual, source: .user)]
        let rest = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 5, head: 10, duration: 10)))
        XCTAssertNil(EditorTimeRange.removing(.init(range: rest, edits: edits, takeDuration: 10)))
        let removed = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 1, head: 3, duration: 10)))
        XCTAssertNil(EditorTimeRange.removing(.init(range: removed, edits: edits, takeDuration: 10)))
    }

    func testRestoringInsideACutKeepsBothOutsidePiecesAndRestorationHistory() throws {
        var edits = TimelineEdits.empty
        let cut = TimelineCut(start: 1, end: 9, kind: .silence, source: .automatic)
        edits.cuts = [cut]
        let range = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 4, head: 6, duration: 10)))
        let restored = try XCTUnwrap(
            EditorTimeRange.restoring(
                .init(
                    range: range, edits: edits, takeDuration: 10
                )))
        XCTAssertEqual(restored.enabledCuts.map(\.start), [1, 6])
        XCTAssertEqual(restored.enabledCuts.map(\.end), [4, 9])
        XCTAssertEqual(restored.cuts.first?.id, cut.id)
        XCTAssertEqual(Set(restored.cuts.map(\.id)).count, 3)
        XCTAssertEqual(restored.cuts.filter { !$0.isEnabled }.map(\.start), [4])
        XCTAssertEqual(restored.cuts.filter { !$0.isEnabled }.map(\.end), [6])
        let map = TimelineTimeMap(takeDuration: CMTime(seconds: 10, preferredTimescale: 600), cuts: restored.cuts)
        XCTAssertEqual(map.outputDuration.seconds, 4, accuracy: 0.001)
        XCTAssertNil(EditorTimeRange.restoring(.init(range: range, edits: restored, takeDuration: 10)))
    }

    func testKeyboardModifiersLeaveSystemAndTextCommandsUntouched() {
        XCTAssertEqual(command(.init(keyCode: 123, characters: "", modifiers: [])), .step(-1))
        XCTAssertEqual(command(.init(keyCode: 124, characters: "", modifiers: .shift)), .seek(1))
        XCTAssertEqual(command(.init(keyCode: 11, characters: "b", modifiers: .command)), .split)
        XCTAssertNil(command(.init(keyCode: 6, characters: "z", modifiers: .command)))
        XCTAssertNil(command(.init(keyCode: 6, characters: "z", modifiers: [.command, .shift])))
        XCTAssertNil(command(.init(keyCode: 34, characters: "i", modifiers: [.command])))
        XCTAssertNil(command(.init(keyCode: 123, characters: "", modifiers: .option)))
        XCTAssertNil(command(.init(keyCode: 49, characters: " ", modifiers: .control)))
    }

    func testRangePlaybackAndZoomShortcuts() {
        XCTAssertEqual(command(.init(keyCode: 34, characters: "i", modifiers: [])), .markIn)
        XCTAssertEqual(command(.init(keyCode: 31, characters: "o", modifiers: [])), .markOut)
        XCTAssertEqual(command(.init(keyCode: 53, characters: "", modifiers: [])), .clearSelection)
        XCTAssertEqual(command(.init(keyCode: 51, characters: "", modifiers: [])), .deleteSelection)
        XCTAssertEqual(command(.init(keyCode: 51, characters: "", modifiers: .shift)), .restoreSelection)
        XCTAssertEqual(command(.init(keyCode: 38, characters: "j", modifiers: [])), .seek(-3))
        XCTAssertEqual(command(.init(keyCode: 40, characters: "k", modifiers: [])), .pause)
        XCTAssertEqual(command(.init(keyCode: 37, characters: "l", modifiers: [])), .playForward)
        XCTAssertEqual(command(.init(keyCode: 24, characters: "+", modifiers: .shift)), .zoomIn)
        XCTAssertEqual(command(.init(keyCode: 27, characters: "-", modifiers: [])), .zoomOut)
        XCTAssertEqual(command(.init(keyCode: 3, characters: "f", modifiers: [])), .fit)
        XCTAssertEqual(command(.init(keyCode: 44, characters: "/", modifiers: .shift)), .showHelp)
    }

    @MainActor
    func testTypingAndNativeControlsKeepTheirKeyboardEvents() {
        XCTAssertFalse(EditorKeyboardCommand.acceptsShortcuts(firstResponder: NSTextView()))
        XCTAssertFalse(EditorKeyboardCommand.acceptsShortcuts(firstResponder: NSTextField()))
        XCTAssertFalse(EditorKeyboardCommand.acceptsShortcuts(firstResponder: NSSlider()))
        XCTAssertTrue(EditorKeyboardCommand.acceptsShortcuts(firstResponder: NSView()))
    }

    @MainActor
    func testRangeCutPersistsAndUndoRedoRestoreTheSavedProject() throws {
        let suite = "EditorSelectionControlsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults), defaults: defaults
        )
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        var settings = RecordingSettings()
        settings.outputDirectory = directory
        settings.enabledSources = [.screen]
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try Data().write(to: take.screenURL)
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let original = try XCTUnwrap(vm.lastExportedProject)
        let range = try XCTUnwrap(EditorTimeRange.resolve(.init(anchor: 2, head: 4, duration: 10)))
        let edits = try XCTUnwrap(
            EditorTimeRange.removing(
                .init(
                    range: range, edits: original.edits, takeDuration: 10
                )))

        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: edits, actionName: "Cut Range")))
        XCTAssertEqual(vm.editorUndoTitle, "Undo Cut Range")
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits, edits)
        vm.undoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits, original.edits)
        vm.redoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits, edits)
        XCTAssertEqual(vm.lastExportedProject?.sceneEvents, original.sceneEvents)
        let restored = try XCTUnwrap(
            EditorTimeRange.restoring(
                .init(
                    range: range, edits: edits, takeDuration: 10
                )))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: restored, actionName: "Restore Range")))
        XCTAssertTrue(try store.loadRecordingProject(at: take.projectURL).edits.enabledCuts.isEmpty)
        vm.undoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits, edits)
    }

    private func command(_ request: EditorKeyboardCommand.Request) -> EditorKeyboardCommand? {
        EditorKeyboardCommand.resolve(request)
    }
}
