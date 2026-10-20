import Foundation
import XCTest
@testable import BlitzRecorderApp

final class ProjectSaveSafetyTests: XCTestCase {
    private var outputDirectory: URL!
    private var settings = RecordingSettings()
    private let store = TakeFileStore()

    override func setUpWithError() throws {
        outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        settings.outputDirectory = outputDirectory
        settings.savesSourceFiles = true
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    func testDamagedLibraryIndexIsKeptAsBackupAndRebuiltFromTakeFolders() throws {
        let first = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_000), title: nil))
        let second = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_100), title: nil))
        let index = store.projectHistoryURL(for: settings)
        try Data("{ not json".utf8).write(to: index)

        let third = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_200), title: nil))

        let paths = Set(store.loadProjectHistory(settings: settings).entries.map(\.projectPath))
        XCTAssertEqual(paths, Set([first, second, third].map(\.projectURL.path)))
        let backups = try FileManager.default.contentsOfDirectory(atPath: index.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("projects.damaged-") }
        XCTAssertEqual(backups.count, 1)
    }

    func testMissingLibraryIndexIsRebuiltInsteadOfStartingEmpty() throws {
        let first = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_000), title: nil))
        try FileManager.default.removeItem(at: store.projectHistoryURL(for: settings))

        let second = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_100), title: nil))

        let paths = Set(store.loadProjectHistory(settings: settings).entries.map(\.projectPath))
        XCTAssertEqual(paths, Set([first.projectURL.path, second.projectURL.path]))
    }

    func testTakeFoldersMissingFromTheIndexAreAddedBack() throws {
        let listed = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_000), title: nil))
        let orphan = try store.createTake(.init(settings: settings, date: Date(timeIntervalSince1970: 1_800_000_100), title: nil))
        let index = store.projectHistoryURL(for: settings)
        var history = try TakeFileStore.projectDecoder().decode(RecordingProjectHistory.self, from: Data(contentsOf: index))
        history.entries.removeAll { $0.projectPath == orphan.projectURL.path }
        try TakeFileStore.projectEncoder().encode(history).write(to: index)

        let paths = Set(store.loadProjectHistory(settings: settings).entries.map(\.projectPath))

        XCTAssertEqual(paths, [listed.projectURL.path, orphan.projectURL.path])
        let saved = try TakeFileStore.projectDecoder().decode(RecordingProjectHistory.self, from: Data(contentsOf: index))
        XCTAssertEqual(saved.entries.count, 2)
    }

    func testEditFromStaleRevisionIsRejectedAndLeavesTheSavedEditAlone() throws {
        let take = try store.createTake(settings: settings)
        let loaded = try store.loadRecordingProject(at: take.projectURL)
        let editGuard = TakeFileStore.ProjectEditGuard(projectURL: take.projectURL, expectedEditRevision: loaded.editRevision)

        var firstEdits = loaded.edits
        firstEdits.videoSplits = [1]
        let saved = try store.editProject(editGuard) {
            try store.updateProjectTimelineEdits(.init(projectURL: take.projectURL, edits: firstEdits, baseSettings: settings))
        }
        XCTAssertEqual(saved.editRevision, loaded.editRevision + 1)

        var staleEdits = loaded.edits
        staleEdits.videoSplits = [2]
        XCTAssertThrowsError(try store.editProject(editGuard) {
            try store.updateProjectTimelineEdits(.init(projectURL: take.projectURL, edits: staleEdits, baseSettings: settings))
        }) { error in
            XCTAssertEqual((error as? ProjectEditConflict)?.current.edits.videoSplits, [1])
        }
        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).edits.videoSplits, [1])
    }

    func testRenameAndExportDoNotInvalidateTheEditorsRevision() throws {
        let take = try store.createTake(settings: settings)
        let revision = try store.loadRecordingProject(at: take.projectURL).editRevision

        _ = try store.renameProject(.init(projectURL: take.projectURL, title: "Launch walkthrough", settings: settings))
        try store.recordCompletedExport(.init(
            projectURL: take.projectURL,
            record: .init(
                id: UUID(), createdAt: Date(), path: outputDirectory.appendingPathComponent("out.mp4").path,
                format: "mp4", resolution: "1080p", framesPerSecond: 30, quality: "balanced", fileSizeBytes: nil
            ),
            settings: settings
        ))

        XCTAssertEqual(try store.loadRecordingProject(at: take.projectURL).editRevision, revision)
    }
}
