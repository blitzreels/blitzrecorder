import XCTest
@testable import BlitzRecorderApp

final class EditorVideoCutsTests: XCTestCase {
    func testSplitAddsPersistentVideoBoundaryWithoutRemovingAnySourceTime() throws {
        let split = try XCTUnwrap(EditorVideoCuts.splitting(.init(edits: .empty, time: 4, duration: 10)))
        XCTAssertEqual(split.videoSplits, [4])
        XCTAssertTrue(split.cuts.isEmpty)
        XCTAssertEqual(TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: split.cuts).outputDuration.seconds, 10)
        let snapshot = RecordingProject.TimelineEditsSnapshot(split)
        let decoded = try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
            from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.edits, split)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertTrue(try JSONDecoder().decode(RecordingProject.TimelineEditsSnapshot.self,
            from: Data("{}".utf8)).edits.videoSplits.isEmpty)
    }

    func testRepeatedSplitAtTheSamePositionIsIdempotent() throws {
        let first = try XCTUnwrap(EditorVideoCuts.splitting(.init(edits: .empty, time: 4, duration: 10)))
        XCTAssertEqual(EditorVideoCuts.splitting(.init(edits: first, time: 4, duration: 10)), first)
        XCTAssertEqual(EditorVideoCuts.splitting(.init(edits: first, time: 4.0001, duration: 10)), first)
        XCTAssertEqual(EditorVideoCuts.range(.init(edits: first, time: 4, duration: 10)), .init(start: 4, end: 10))
    }

    func testVideoSelectionUsesCutsAndKeptFootageBoundaries() throws {
        var edits = TimelineEdits.empty
        edits.videoSplits = [2, 6]
        edits.cuts = [.init(start: 3, end: 4, kind: .silence, source: .automatic)]
        XCTAssertEqual(EditorVideoCuts.range(.init(edits: edits, time: 5, duration: 10)), .init(start: 4, end: 6))
        XCTAssertNil(EditorVideoCuts.splitting(.init(edits: edits, time: 3.5, duration: 10)))
        for time in [0, 10, -1, .nan, .infinity] {
            XCTAssertNil(EditorVideoCuts.splitting(.init(edits: edits, time: time, duration: 10)))
        }
        let range = try XCTUnwrap(EditorVideoCuts.range(.init(edits: edits, time: 5, duration: 10)))
        let removed = try XCTUnwrap(EditorTimeRange.removing(.init(range: range, edits: edits, takeDuration: 10)))
        XCTAssertEqual(TimelineTimeMap(takeDuration: TimelineTimeMap.time(10), cuts: removed.cuts).removedDuration, 3)
        XCTAssertEqual(removed.videoSplits, edits.videoSplits)
    }

    @MainActor
    func testVideoSplitAndDeleteSaveWithoutChangingScenesAndUndoIndependently() async throws {
        let fixture = try SyntheticRecording()
        try await fixture.writeVideo(.init(url: fixture.take.screenURL, frames: 300))
        let suite = "VideoCutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TakeFileStore()
        let vm = RecorderViewModel(
            coordinator: RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults),
            previewStage: PreviewStageView()
        )
        vm.settings = fixture.settings
        vm.openProject(try XCTUnwrap(store.loadProjectHistory(settings: fixture.settings).entries.first))
        let original = try XCTUnwrap(vm.lastExportedProject)
        let split = try XCTUnwrap(EditorVideoCuts.splitting(.init(edits: original.edits, time: 4, duration: 10)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: split, actionName: "Split Video")))
        let saved = try store.loadRecordingProject(at: fixture.take.projectURL)
        XCTAssertEqual(saved.sceneEvents, original.sceneEvents)
        XCTAssertEqual(saved.edits.videoSplits, [4])
        vm.undoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, original.edits)
        vm.redoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, split)
        let deleted = try XCTUnwrap(EditorTimeRange.removing(.init(
            range: .init(start: 0, end: 4), edits: split, takeDuration: 10)))
        XCTAssertTrue(vm.applyTimelineEdits(.init(edits: deleted, actionName: "Delete Video")))
        XCTAssertEqual(vm.lastExportedProject?.sceneEvents, original.sceneEvents)
        vm.undoEditor()
        XCTAssertEqual(vm.lastExportedProject?.edits, split)
    }
}
