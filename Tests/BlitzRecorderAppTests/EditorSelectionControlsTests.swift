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
        XCTAssertEqual(command(.init(keyCode: 117, characters: "", modifiers: [])), .deleteSelection)
        XCTAssertEqual(command(.init(keyCode: 51, characters: "", modifiers: .shift)), .restoreSelection)
        XCTAssertEqual(command(.init(keyCode: 38, characters: "j", modifiers: [])), .seek(-3))
        XCTAssertEqual(command(.init(keyCode: 40, characters: "k", modifiers: [])), .pause)
        XCTAssertEqual(command(.init(keyCode: 37, characters: "l", modifiers: [])), .playForward)
        XCTAssertEqual(command(.init(keyCode: 24, characters: "+", modifiers: .shift)), .zoomIn)
        XCTAssertEqual(command(.init(keyCode: 27, characters: "-", modifiers: [])), .zoomOut)
        XCTAssertEqual(command(.init(keyCode: 3, characters: "f", modifiers: [])), .fit)
        XCTAssertEqual(command(.init(keyCode: 44, characters: "/", modifiers: .shift)), .showHelp)
    }

    func testDeleteOnASelectedAudioAssetMutesInsteadOfCuttingTheClip() {
        XCTAssertEqual(
            EditorDeleteRouting.action(.init(
                selection: .asset("microphone"), hasPrivacySelection: false, assetIsToggleable: true
            )),
            .toggleAsset
        )
        XCTAssertNil(
            EditorDeleteRouting.action(.init(
                selection: .asset("microphone"), hasPrivacySelection: false, assetIsToggleable: false
            ))
        )
        XCTAssertEqual(
            EditorDeleteRouting.action(.init(
                selection: .range(.init(start: 1, end: 3)), hasPrivacySelection: false, assetIsToggleable: true
            )),
            .cutRange
        )
        XCTAssertEqual(
            EditorDeleteRouting.action(.init(
                selection: .placed(.init(kind: .text, value: UUID())),
                hasPrivacySelection: false, assetIsToggleable: true
            )),
            .removePlaced
        )
        XCTAssertEqual(
            EditorDeleteRouting.action(.init(
                selection: .silenceRange(.init(start: 1, end: 2)),
                hasPrivacySelection: false, assetIsToggleable: true
            )),
            .toggleSilence
        )
        XCTAssertEqual(
            EditorDeleteRouting.help(.toggleAsset),
            "Mute or hide the selected track (Delete). Undo with ⌘Z."
        )
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

    @MainActor
    func testSplitAndDeleteSegmentKeepsEverySourceInSyncAndPersistsUndoRedo() throws {
        let suite = "LinkedSegmentTests.\(UUID().uuidString)"
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
        settings.enabledSources = [.screen, .camera, .microphone, .systemAudio]
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try Data().write(to: take.screenURL)
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let original = try XCTUnwrap(vm.lastExportedProject)

        XCTAssertFalse(vm.deleteProjectSegment(.init(index: 0, duration: 10)))
        XCTAssertFalse(vm.deleteProjectSegment(.init(index: -1, duration: 10)))
        XCTAssertTrue(vm.splitProjectScene(at: 3, duration: 10))
        XCTAssertTrue(vm.splitProjectScene(at: 6, duration: 10))
        let splitEvents = try XCTUnwrap(vm.lastExportedProject?.sceneEvents)
        XCTAssertTrue(vm.deleteProjectSegment(.init(index: 1, duration: 10)))
        let deleted = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(deleted.sceneEvents, splitEvents)
        XCTAssertEqual(deleted.settings, original.settings)
        XCTAssertEqual(deleted.edits.enabledCuts.map(\.start), [3])
        XCTAssertEqual(deleted.edits.enabledCuts.map(\.end), [6])
        XCTAssertEqual(vm.editorUndoTitle, "Undo Delete Segment")

        let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: deleted.edits.cuts)
        XCTAssertEqual(map.outputDuration.seconds, 7, accuracy: 0.001)
        for offset in [0.0, 0.25, -0.1, 0.4] {
            let pieces = map.mediaInsertions(.init(
                activeTakeStart: TimelineTimeMap.time(max(0, offset)),
                sourceTimeAtActiveStart: TimelineTimeMap.time(max(0, -offset)),
                sourceEnd: TimelineTimeMap.time(10 - offset)
            ))
            let afterCut = try XCTUnwrap(pieces.last)
            XCTAssertEqual(pieces.count, 2)
            XCTAssertEqual(afterCut.compositionStart.seconds, 3, accuracy: 0.001)
            XCTAssertEqual(afterCut.sourceStart.seconds, 6 - offset, accuracy: 0.001)
            XCTAssertEqual(afterCut.duration.seconds, 4, accuracy: 0.001)
        }

        vm.undoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits, original.edits)
        vm.redoEditor()
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits, deleted.edits)

        let projection = EditorTimelineProjection(.init(duration: 10, cuts: deleted.edits.cuts))
        XCTAssertTrue(vm.splitProjectScene(at: projection.takeTime(4), duration: 10))
        XCTAssertTrue(vm.deleteProjectSegment(.init(index: 2, duration: 10)))
        let repeated = try store.loadRecordingProject(at: take.projectURL)
        let repeatedMap = TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: repeated.edits.cuts)
        XCTAssertEqual(repeatedMap.outputDuration.seconds, 6, accuracy: 0.001)
        XCTAssertEqual(repeatedMap.takeSeconds(forOutputSeconds: 3), 7, accuracy: 0.001)
        vm.undoEditor()
        vm.undoEditor()

        XCTAssertTrue(vm.deleteProjectSegment(.init(index: 0, duration: 10)))
        XCTAssertEqual(vm.lastExportedProject?.edits.enabledCuts.last?.start, 0)
        XCTAssertEqual(vm.lastExportedProject?.edits.enabledCuts.last?.end, 3)
        XCTAssertFalse(vm.deleteProjectSegment(.init(index: 2, duration: 10)))
        vm.undoEditor()
        XCTAssertTrue(vm.deleteProjectSegment(.init(index: 2, duration: 10)))
        XCTAssertEqual(vm.lastExportedProject?.edits.enabledCuts.last?.start, 6)
        XCTAssertEqual(vm.lastExportedProject?.edits.enabledCuts.last?.end, 10)
    }

    func testMarkInKeepsExistingEndUnlessPlayheadIsLater() throws {
        let extended = try XCTUnwrap(EditorTimeRange.markIn(time: 2, existingEnd: 6, duration: 10))
        XCTAssertEqual(extended.start, 2)
        XCTAssertEqual(extended.end, 6)
        let collapsed = try XCTUnwrap(EditorTimeRange.markIn(time: 8, existingEnd: 6, duration: 10))
        XCTAssertEqual(collapsed.start, 8)
        XCTAssertEqual(collapsed.end, 8)
        let fresh = try XCTUnwrap(EditorTimeRange.markIn(time: 3, existingEnd: nil, duration: 10))
        XCTAssertEqual(fresh.start, 3)
        XCTAssertEqual(fresh.end, 10)
    }

    func testMarkOutKeepsExistingStartUnlessPlayheadIsEarlier() throws {
        let extended = try XCTUnwrap(EditorTimeRange.markOut(time: 7, existingStart: 2, duration: 10))
        XCTAssertEqual(extended.start, 2)
        XCTAssertEqual(extended.end, 7)
        let collapsed = try XCTUnwrap(EditorTimeRange.markOut(time: 1, existingStart: 2, duration: 10))
        XCTAssertEqual(collapsed.start, 1)
        XCTAssertEqual(collapsed.end, 1)
        let fresh = try XCTUnwrap(EditorTimeRange.markOut(time: 4, existingStart: nil, duration: 10))
        XCTAssertEqual(fresh.start, 0)
        XCTAssertEqual(fresh.end, 4)
    }

    func testKeyboardSessionIgnoresSettingsAndShowsHelpWithoutPlayback() {
        XCTAssertEqual(
            EditorKeyboardSession.resolve(.init(
                isShowingSettings: true,
                isExportPopoverPresented: false,
                showsTimelineShortcuts: false,
                isFinishing: false,
                isPlaybackReady: true,
                keyCode: 49,
                characters: " ",
                modifiers: []
            )),
            .ignore
        )
        XCTAssertEqual(
            EditorKeyboardSession.resolve(.init(
                isShowingSettings: false,
                isExportPopoverPresented: false,
                showsTimelineShortcuts: false,
                isFinishing: false,
                isPlaybackReady: false,
                keyCode: 49,
                characters: " ",
                modifiers: []
            )),
            .ignore
        )
        XCTAssertEqual(
            EditorKeyboardSession.resolve(.init(
                isShowingSettings: false,
                isExportPopoverPresented: false,
                showsTimelineShortcuts: false,
                isFinishing: false,
                isPlaybackReady: false,
                keyCode: 44,
                characters: "?",
                modifiers: []
            )),
            .showHelp
        )
        XCTAssertEqual(
            EditorKeyboardSession.resolve(.init(
                isShowingSettings: false,
                isExportPopoverPresented: false,
                showsTimelineShortcuts: false,
                isFinishing: false,
                isPlaybackReady: true,
                keyCode: 49,
                characters: " ",
                modifiers: []
            )),
            .command(.togglePlayback)
        )
    }

    func testAssetTracksSnapshotIsOnePass() {
        let snapshot = EditorAssetTracks.snapshot(.init(
            assets: [
                .init(id: "s", kind: .screen),
                .init(id: "c", kind: .camera),
                .init(id: "m", kind: .microphone)
            ],
            hiddenKinds: [.camera],
            hideableKinds: [.screen, .camera],
            mutedSources: [.microphone],
            muteableSources: [.microphone]
        ))
        XCTAssertEqual(snapshot.hiddenIDs, ["c"])
        XCTAssertEqual(snapshot.mutedIDs, ["m"])
        XCTAssertEqual(snapshot.toggleableIDs, ["c", "m"])
        XCTAssertEqual(EditorAssetTracks.layerKind(.screen), .screen)
        XCTAssertEqual(EditorAssetTracks.audioSource(.microphone), .microphone)
    }

    func testRestoringTogetherNoopsWhenNothingIsCut() {
        XCTAssertNil(EditorTimeRange.restoringTogether(.init(
            ranges: [EditorTimeRange(start: 1, end: 2)],
            kind: .manual,
            edits: .empty,
            takeDuration: 10
        )))
    }
}
