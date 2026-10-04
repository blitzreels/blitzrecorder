import XCTest
@testable import BlitzRecorderApp

final class ProjectFoldersTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLessonCodesMakeNumberedFoldersAndLegacyCodesStillParse() throws {
        let legacy = try XCTUnwrap(ProjectFolderTitle.coded("Formation IA - S01E05 - Lesson - Part two"))
        XCTAssertEqual(legacy.folder?.segments, ["Formation IA"])
        XCTAssertEqual(legacy.title, "Lesson - Part two")
        XCTAssertEqual(legacy.formatted, "Formation IA - M01L05 - Lesson - Part two")
        XCTAssertNil(ProjectFolderTitle.coded(" - S01E05 - Lesson"))
    }

    func testSharedPrefixesBecomeNestedFoldersButSingleTitlesStayPlain() {
        let first = entry(.init(title: "Clients - Acme - Kickoff", daysAgo: 2))
        let second = entry(.init(title: "Clients - Acme - Review", daysAgo: 1))
        let lone = entry(.init(title: "Product demo - v2", daysAgo: 1))
        let index = ProjectFolderIndex(.init(projects: [first, second, lone], pins: []))
        XCTAssertEqual(index.resolved(first).folder?.segments, ["Clients", "Acme"])
        XCTAssertEqual(index.resolved(first).title, "Kickoff")
        XCTAssertNil(index.resolved(lone).folder)
        let roots = ProjectFolderTree.roots(.init(projects: [first, second, lone], index: index, includesEmpty: true))
        XCTAssertEqual(roots.map(\.path.name), ["Clients"])
        XCTAssertEqual(roots[0].children.map(\.path.name), ["Acme"])
        XCTAssertEqual(roots[0].allProjects.count, 2)
    }

    func testPinnedFolderClaimsSingleRecordingAndStaysWhenEmpty() {
        let lone = entry(.init(title: "Product demo - v2", daysAgo: 1))
        let pins = [ProjectFolderPin(path: ["Product demo"], modules: [], numbered: false),
                    ProjectFolderPin(path: ["Empty"], modules: [], numbered: false)]
        let index = ProjectFolderIndex(.init(projects: [lone], pins: pins))
        XCTAssertEqual(index.resolved(lone).title, "v2")
        XCTAssertEqual(ProjectFolderTree.roots(.init(projects: [lone], index: index, includesEmpty: true)).map(\.path.name),
                       ["Empty", "Product demo"])
        XCTAssertEqual(ProjectFolderTree.roots(.init(projects: [lone], index: index, includesEmpty: false)).count, 1)
    }

    func testMovingIntoPlainAndNumberedFolders() throws {
        let path = try XCTUnwrap(ProjectFolderPath(["Clients", "Acme"]))
        let loose = entry(.init(title: "2026-10-01-10-00-00", daysAgo: 1))
        let lesson1 = entry(.init(title: "Course - M01L01 - Intro", daysAgo: 3))
        let lesson4 = entry(.init(title: "Course - M01L04 - Setup", daysAgo: 2))
        let library = [loose, lesson1, lesson4]
        let index = ProjectFolderIndex(.init(projects: library, pins: []))
        XCTAssertEqual(ProjectFolderMoves.titles(.init(moving: [loose], destination: .folder(path: path, module: nil, before: nil),
                                                       index: index, library: library)),
                       [loose.id: "Clients - Acme - Untitled"])
        let course = try XCTUnwrap(ProjectFolderPath(["course"]))
        XCTAssertEqual(ProjectFolderMoves.titles(.init(moving: [loose], destination: .folder(path: course, module: 1, before: nil),
                                                       index: index, library: library)),
                       [loose.id: "Course - M01L05 - Untitled"])
        XCTAssertEqual(ProjectFolderMoves.titles(.init(moving: [lesson4], destination: .folder(path: course, module: 1, before: lesson1.id),
                                                       index: index, library: library)),
                       [lesson4.id: "Course - M01L01 - Setup", lesson1.id: "Course - M01L02 - Intro"])
        XCTAssertEqual(ProjectFolderMoves.titles(.init(moving: [lesson1], destination: .loose, index: index, library: library)),
                       [lesson1.id: "Intro"])
    }

    func testRenameNextTitleAndAutoTitlePrefix() throws {
        let first = entry(.init(title: "Clients - Acme - Kickoff", daysAgo: 2))
        let second = entry(.init(title: "Clients - Acme - Review", daysAgo: 1))
        let index = ProjectFolderIndex(.init(projects: [first, second], pins: []))
        let clients = try XCTUnwrap(ProjectFolderPath(["Clients"]))
        let renamed = ProjectFolderMoves.titles(ProjectFolderMoves.RenameRequest(
            replacement: .init(from: clients, to: try XCTUnwrap(ProjectFolderPath(["Customers"]))), index: index, library: [first, second]
        ))
        XCTAssertEqual(renamed[first.id], "Customers - Acme - Kickoff")
        let acme = try XCTUnwrap(ProjectFolderPath(["Clients", "Acme"]))
        let next = ProjectFolderMoves.nextTitle(.init(target: .init(path: acme, module: nil), index: index, library: [first, second]))
        XCTAssertEqual(next.formatted, "Clients - Acme - Untitled")
        XCTAssertEqual(ProjectFolderTitle.untitledPrefix("Clients - Acme - Untitled"), "Clients - Acme - ")
        XCTAssertNil(ProjectFolderTitle.untitledPrefix("Clients - Acme - Review"))
        XCTAssertFalse(ProjectFolderPath.isValidName("A - B"))
        XCTAssertFalse(ProjectFolderPath.isValidName("M01L02"))
    }

    private struct EntryRequest {
        let title: String
        let daysAgo: Double
    }

    private func entry(_ request: EntryRequest) -> RecordingProjectHistory.Entry {
        let date = now.addingTimeInterval(-request.daysAgo * 86_400)
        return .init(id: UUID(), title: request.title, projectPath: "/unused", takeDirectoryPath: "/unused",
                     finalVideoPath: nil, createdAt: date, updatedAt: date, exports: nil)
    }
}
