import XCTest
@testable import BlitzRecorderApp

final class ProjectLibraryLocationsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("libraries-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func library(_ name: String, takes: Int) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        for index in 0..<takes {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("BlitzRecorder Source Takes/take-\(index)", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return folder
    }

    func testEveryLibraryReportsItsDiskAndRecordings() throws {
        let recordings = try library("recordings", takes: 3)
        _ = try library("course", takes: 1)
        let unplugged = URL(fileURLWithPath: "/Volumes/unplugged-\(UUID().uuidString)/recordings", isDirectory: true)
        let locations = ProjectLibraryLocations.scan(.init(
            libraries: [.init(url: recordings, bookmarkData: nil), .init(url: unplugged, bookmarkData: nil)],
            destination: .init(url: recordings, bookmarkData: nil),
            searchRoots: [root]
        ))

        XCTAssertEqual(locations.locations.map(\.recordingCount), [3, nil])
        XCTAssertEqual(locations.locations.map(\.isRecordingDestination), [true, false])
        XCTAssertEqual(locations.offline.map(\.url), [unplugged.standardizedFileURL])
        XCTAssertTrue(locations.offline[0].diskName.hasPrefix("unplugged-"), "an unplugged disk keeps its name")
        XCTAssertEqual(locations.suggestions.map(\.url.lastPathComponent), ["course"],
                       "a library on a connected disk the app does not read yet is offered")
        XCTAssertEqual(locations.suggestions.first?.recordingCount, 1)
    }

    func testAnIndexCountsItsEntries() throws {
        let folder = try library("indexed", takes: 0)
        let index = folder.appendingPathComponent("BlitzRecorder Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        try Data(#"{"version":1,"entries":[{},{}]}"#.utf8).write(to: index.appendingPathComponent("projects.json"))
        XCTAssertEqual(ProjectLibraryLocations.recordingCount(in: folder), 2)
        XCTAssertNil(ProjectLibraryLocations.recordingCount(in: root.appendingPathComponent("empty")))
    }
}
