import Foundation
import XCTest
@testable import BlitzRecorderApp

final class ProjectRenameTests: XCTestCase {
    func testOnlyTimestampTitlesAreEligibleForAutomaticRename() {
        XCTAssertTrue(RecordingProjectDisplayTitle.isUntitled("2026-07-28-15-57-24"))
        XCTAssertFalse(RecordingProjectDisplayTitle.isUntitled("Building an AI Video Editor"))
    }

    func testTimestampProjectDisplayTitleUsesRecordingDateInsteadOfEditDate() {
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = createdAt.addingTimeInterval(3_600)
        let entry = RecordingProjectHistory.Entry(
            id: UUID(),
            title: "2026-07-28-15-57-24",
            projectPath: "/tmp/project.json",
            takeDirectoryPath: "/tmp/take",
            finalVideoPath: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            exports: nil
        )

        XCTAssertEqual(
            entry.displayTitle,
            "Recording at \(createdAt.formatted(date: .omitted, time: .shortened))"
        )
        XCTAssertNotEqual(
            entry.displayTitle,
            "Recording at \(updatedAt.formatted(date: .omitted, time: .shortened))"
        )
    }

    func testLegacyRenamedProjectRecoversRecordingDateFromTakeDirectory() {
        let updatedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let entry = RecordingProjectHistory.Entry(
            id: UUID(),
            title: "Client strategy call",
            projectPath: "/tmp/2026-07-20-14-31-05/project.blitzrecorder.json",
            takeDirectoryPath: "/tmp/2026-07-20-14-31-05",
            finalVideoPath: nil,
            createdAt: nil,
            updatedAt: updatedAt,
            exports: nil
        )

        XCTAssertEqual(
            entry.recordedAt,
            RecordingProjectDisplayTitle.timestampDate(from: "2026-07-20-14-31-05")
        )
        XCTAssertNotEqual(entry.recordedAt, updatedAt)
    }

    func testRenamePersistsProjectTitleAndHistory() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        var settings = RecordingSettings()
        settings.outputDirectory = outputDirectory
        settings.savesSourceFiles = true

        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        let renamed = try store.renameProject(RecordingProjectRenameRequest(
            projectURL: take.projectURL,
            title: "  Client launch walkthrough  ",
            settings: settings
        ))

        let reloaded = try store.loadRecordingProject(at: take.projectURL)
        let history = store.loadProjectHistory(settings: settings)

        XCTAssertEqual(renamed.title, "Client launch walkthrough")
        XCTAssertEqual(reloaded.title, "Client launch walkthrough")
        XCTAssertEqual(history.entries.first?.title, "Client launch walkthrough")
        XCTAssertEqual(history.entries.first?.id, renamed.id)
    }

    func testProjectHistorySortsByRecordingDateInsteadOfEditDate() throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        var settings = RecordingSettings()
        settings.outputDirectory = outputDirectory
        let olderRecording = RecordingProjectHistory.Entry(
            id: UUID(),
            title: "Older edited project",
            projectPath: "/tmp/older.json",
            takeDirectoryPath: "/tmp/older",
            finalVideoPath: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_900_000_000),
            exports: nil
        )
        let newerRecording = RecordingProjectHistory.Entry(
            id: UUID(),
            title: "Newer recording",
            projectPath: "/tmp/newer.json",
            takeDirectoryPath: "/tmp/newer",
            finalVideoPath: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            exports: nil
        )
        let history = RecordingProjectHistory(
            version: 1,
            entries: [olderRecording, newerRecording]
        )
        let historyURL = TakeFileStore().projectHistoryURL(for: settings)
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: historyURL)

        let loaded = TakeFileStore().loadProjectHistory(settings: settings)

        XCTAssertEqual(loaded.entries.map(\.id), [newerRecording.id, olderRecording.id])
    }
}

extension ProjectRenameTests {
    func testExportCompletionPreservesRenameAndEditsMadeWhileRendering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = RecordingSettings()
        settings.outputDirectory = directory
        settings.savesSourceFiles = true
        let store = TakeFileStore()
        let take = try store.createTake(settings: settings)
        _ = try store.renameProject(.init(projectURL: take.projectURL, title: "New course title", settings: settings))
        let record = RecordingProject.ExportRecord(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            path: directory.appendingPathComponent("old-export-name.mp4").path,
            format: "mp4", resolution: "1080p", framesPerSecond: 30, quality: "high", fileSizeBytes: 100)
        var edits = TimelineEdits.empty
        edits.cuts = [.init(start: 2, end: 3, kind: .manual, source: .user)]
        let before = try store.updateProjectTimelineEdits(.init(
            projectURL: take.projectURL, edits: edits, baseSettings: settings))
        try store.recordCompletedExport(.init(projectURL: take.projectURL, record: record, settings: settings))
        let after = try store.loadRecordingProject(at: take.projectURL)
        XCTAssertEqual(after.title, "New course title")
        XCTAssertEqual(after.settings, before.settings)
        XCTAssertEqual(after.sceneEvents, before.sceneEvents)
        XCTAssertEqual(after.editorState, before.editorState)
        XCTAssertEqual(after.edits, before.edits)
        XCTAssertEqual(after.exports, [record])
        XCTAssertEqual(after.finalVideoPath, record.path)
        XCTAssertEqual(store.loadProjectHistory(settings: settings).entries.first?.title, after.title)
    }
}
