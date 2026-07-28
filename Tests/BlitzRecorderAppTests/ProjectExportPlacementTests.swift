@testable import BlitzRecorderApp
import XCTest

final class ProjectExportPlacementTests: XCTestCase {
    func testTranscriptTitleBecomesExportFilenameSlug() {
        XCTAssertEqual(
            ProjectExportFilename.slug(
                from: "Testing Transcription & Title Generation on Large Screens"
            ),
            "testing-transcription-title-generation-on-large-screens"
        )
    }

    func testEmptyTitleUsesExportFallback() {
        XCTAssertEqual(ProjectExportFilename.slug(from: "---"), "blitzrecorder-export")
    }

    func testPlacesExportAtChosenDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderedURL = directory.appendingPathComponent("rendered.mov")
        let destinationURL = directory.appendingPathComponent("chosen.mov")
        try Data("video".utf8).write(to: renderedURL)

        let result = try ProjectExportPlacement.place(ProjectExportPlacementRequest(
            renderedURL: renderedURL,
            destinationURL: destinationURL
        ))

        XCTAssertEqual(result, destinationURL)
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("video".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renderedURL.path))
    }

    func testReplacesConfirmedDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let renderedURL = directory.appendingPathComponent("rendered.mp4")
        let destinationURL = directory.appendingPathComponent("chosen.mp4")
        try Data("new video".utf8).write(to: renderedURL)
        try Data("old video".utf8).write(to: destinationURL)

        _ = try ProjectExportPlacement.place(ProjectExportPlacementRequest(
            renderedURL: renderedURL,
            destinationURL: destinationURL
        ))

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new video".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renderedURL.path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectExportPlacementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
