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
}
