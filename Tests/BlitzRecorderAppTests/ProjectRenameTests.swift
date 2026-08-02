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
