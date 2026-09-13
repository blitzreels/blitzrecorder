import XCTest
@testable import BlitzRecorderApp

final class EditorPlacedItemTests: XCTestCase {
    private var edits: TimelineEdits {
        var edits = TimelineEdits.empty
        edits.privacyMasks = [.init(id: UUID(), source: .screen,
            frame: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), start: 1, end: 7, style: .blur)]
        edits.textOverlays = [.init(start: 1, end: 7, text: "Title", frame: .init(x: 0, y: 0, width: 1, height: 0.2), style: .title),
                              .init(start: 2, end: 6, text: "Caption", frame: .init(x: 0, y: 0.8, width: 1, height: 0.2), style: .caption)]
        edits.zoom.keyframes = [.init(time: 0, amount: 0, position: .zero),
                                .init(time: 3, amount: 0.5, position: .init(x: 0.5, y: 0.5))]
        edits.cuts = [.init(start: 3, end: 5, kind: .manual, source: .user)]
        return edits
    }

    func testOverlappingItemsHaveSeparateRowsAndZoomPointsShareOneTrack() {
        var source = edits
        source.zoom.isEnabled = false
        let tracks = EditorPlacedTrack.resolve(source)
        XCTAssertEqual(tracks.count, 4)
        XCTAssertEqual(tracks.map(\.items.count), [1, 1, 1, 2])
        XCTAssertEqual(tracks[0].items[0].id.value, source.privacyMasks[0].id)
        XCTAssertEqual(tracks[1].items[0].title, "Title")
        XCTAssertEqual(tracks[2].items[0].title, "Caption")
        XCTAssertTrue(tracks[3].items.allSatisfy { $0.isPoint && !$0.isEnabled })
    }

    func testMovePreservesVisibleDurationAcrossCutsAndTrimEndsOnTheCorrectSideOfASeam() throws {
        let source = edits
        let item = try XCTUnwrap(EditorPlacedTrack.resolve(source).first?.items.first)
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: source.cuts))
        let moved = EditorPlacedItemEditing.timing(.init(item: item, delta: 1, gesture: .move, projection: projection))
        XCTAssertEqual(moved.start, 2, accuracy: 0.002)
        XCTAssertEqual(moved.end, 8, accuracy: 0.002)
        let trimmed = EditorPlacedItemEditing.timing(.init(item: item, delta: -2, gesture: .trimEnd, projection: projection))
        XCTAssertEqual(trimmed.start, 1, accuracy: 0.002)
        XCTAssertEqual(trimmed.end, 3, accuracy: 0.002)
        let clamped = EditorPlacedItemEditing.timing(.init(item: item, delta: -100, gesture: .move, projection: projection))
        XCTAssertEqual(clamped.start, 0, accuracy: 0.002)
        XCTAssertEqual(projection.displayTime(clamped.end) - projection.displayTime(clamped.start), 4, accuracy: 0.002)
    }

    func testMaskTimingAndDeletionPreserveOtherItemsSourcesAndCuts() throws {
        let source = edits
        let id = EditorPlacedItem.ID(kind: .mask, value: source.privacyMasks[0].id)
        let changed = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: source,
            change: .init(id: id, timing: .init(start: 2, end: 9)))))
        XCTAssertEqual(changed.privacyMasks[0].frame, source.privacyMasks[0].frame)
        XCTAssertEqual(changed.privacyMasks[0].style, source.privacyMasks[0].style)
        XCTAssertEqual(changed.privacyMasks[0].start, 2)
        let removed = EditorPlacedItemEditing.removing(.init(edits: changed, id: id))
        XCTAssertTrue(removed.privacyMasks.isEmpty)
        XCTAssertEqual(removed.textOverlays, source.textOverlays)
        XCTAssertEqual(removed.zoom, source.zoom)
        XCTAssertEqual(removed.cuts, source.cuts)
    }

    func testItemPreviewSeeksInsideVisibleContentAfterFractionalMovesAndAcrossCutSeams() {
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: edits.cuts))
        let moved = EditorPlacedItem.Timing(start: 2.498734, end: 7.92)
        XCTAssertGreaterThan(moved.previewTime(projection), moved.start)
        XCTAssertLessThan(moved.previewTime(projection), moved.end)
        let atSeam = EditorPlacedItem.Timing(start: 2.995, end: 6)
        XCTAssertGreaterThan(atSeam.previewTime(projection), 5)
        let short = EditorPlacedItem.Timing(start: 2, end: 2.006)
        XCTAssertLessThan(short.previewTime(projection), short.end)
        let point = EditorPlacedItem.Timing(start: 6, end: 6)
        XCTAssertEqual(point.previewTime(projection), 6)
    }

    func testSplitOnlyDividesTheSelectedOverlayAndKeepsGeometry() throws {
        let source = edits
        let id = EditorPlacedItem.ID(kind: .text, value: source.textOverlays[0].id)
        let split = try XCTUnwrap(EditorPlacedItemEditing.splitting(.init(edits: source, id: id, time: 2)))
        XCTAssertEqual(split.textOverlays.count, 3)
        XCTAssertEqual(split.textOverlays[0].id, id.value)
        XCTAssertNotEqual(split.textOverlays[1].id, id.value)
        XCTAssertEqual(split.textOverlays[0].end, 2)
        XCTAssertEqual(split.textOverlays[1].start, 2)
        XCTAssertEqual(split.textOverlays[1].end, 7)
        XCTAssertEqual(split.textOverlays[1].frame, source.textOverlays[0].frame)
        XCTAssertEqual(split.cuts, source.cuts)
        XCTAssertEqual(split.privacyMasks, source.privacyMasks)
        XCTAssertNil(EditorPlacedItemEditing.splitting(.init(edits: source, id: id, time: 1)))
    }

    func testZoomMovesInOutputTimeAndRemainsSorted() throws {
        let source = edits
        let item = try XCTUnwrap(EditorPlacedTrack.resolve(source).last?.items.first)
        let projection = EditorTimelineProjection(.init(duration: 10, cuts: source.cuts))
        let timing = EditorPlacedItemEditing.timing(.init(item: item, delta: 6, gesture: .move, projection: projection))
        let changed = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: source,
            change: .init(id: item.id, timing: timing))))
        XCTAssertEqual(changed.zoom.keyframes.map(\.time), [3, 8])
        XCTAssertEqual(changed.zoom.keyframes.last?.id, item.id.value)
        XCTAssertEqual(changed.zoom.keyframes.last?.amount, 0)
    }

    func testMusicReflectsItsFullExportScopeWithoutOfferingUnsupportedTrimming() throws {
        let id = UUID()
        XCTAssertNil(EditorPlacedTrack.music(.init(projectID: id, path: nil, duration: 10)))
        let track = try XCTUnwrap(EditorPlacedTrack.music(.init(projectID: id, path: "/tmp/music.wav", duration: 10)))
        let item = try XCTUnwrap(track.items.first)
        XCTAssertFalse(item.canChangeTiming)
        let timing = EditorPlacedItemEditing.timing(.init(item: item, delta: 2, gesture: .trimStart,
            projection: .init(.init(duration: 10, cuts: []))))
        XCTAssertEqual(timing, item.timing)
    }

    @MainActor
    func testVariantTextTimingPersistsAndUndoRestoresItWithoutChangingOriginalText() throws {
        let suite = "PlacedItemTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        var settings = RecordingSettings()
        settings.outputDirectory = directory
        settings.enabledSources = [.screen]
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        try Data().write(to: take.screenURL)
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first))
        let source = edits
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: source, actionName: "Add Items")))
        vm.selectOutputLayout(.square)
        let variant = try XCTUnwrap(vm.editorProject?.edits)
        let id = EditorPlacedItem.ID(kind: .text, value: variant.textOverlays[0].id)
        let changed = try XCTUnwrap(EditorPlacedItemEditing.changing(.init(edits: variant,
            change: .init(id: id, timing: .init(start: 2, end: 9)))))
        XCTAssertTrue(vm.applyOutputTextEdits(.init(edits: changed, actionName: "Change Item Timing")))
        var saved = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(saved.edits.textOverlays[0].start, 1)
        XCTAssertEqual(saved.outputProject.edits.textOverlays[0].start, 2)
        XCTAssertEqual(saved.edits.privacyMasks, source.privacyMasks)
        vm.undoEditor()
        saved = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(saved.outputProject.edits.textOverlays[0].start, 1)
        vm.redoEditor()
        saved = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(saved.outputProject.edits.textOverlays[0].end, 9)
        XCTAssertEqual(saved.edits.cuts, source.cuts)
        vm.prepareForWindowClose()
    }
}
