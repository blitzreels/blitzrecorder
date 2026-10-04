import XCTest
@testable import BlitzRecorderApp

final class ProjectRenameDraftTests: XCTestCase {
    func testChangingOnlyLessonPreservesNestedPathAndLegacyCode() throws {
        let name = "Courses - Formation IA - S01E06 - Développement - Part two"
        let resolved = try XCTUnwrap(ProjectFolderTitle.coded(name))
        var draft = ProjectRenameDraft(.init(original: name, resolved: resolved))
        XCTAssertEqual(draft.proposedTitle, name)
        XCTAssertEqual(draft.lesson, "06")
        draft.lesson = "05"
        XCTAssertEqual(draft.proposedTitle, "Courses - Formation IA - S01E05 - Développement - Part two")
        XCTAssertEqual(draft.folder?.displayPath, "Courses › Formation IA")
    }

    func testTitleEditPreservesOriginalNumberFormat() throws {
        let name = "Course - M1L006 - Before"
        var draft = ProjectRenameDraft(.init(original: name, resolved: try XCTUnwrap(ProjectFolderTitle.coded(name))))
        draft.title = "After"
        XCTAssertEqual(draft.proposedTitle, "Course - M1L006 - After")
    }

    func testInvalidLessonDoesNotProduceRename() throws {
        let name = "Course - M01L06 - Before"
        var draft = ProjectRenameDraft(.init(original: name, resolved: try XCTUnwrap(ProjectFolderTitle.coded(name))))
        for invalid in ["", "-1", "1.5", "abc", "10000", "９"] {
            draft.lesson = invalid
            XCTAssertNil(draft.proposedTitle, invalid)
            XCTAssertNotNil(draft.validationMessage, invalid)
        }
        draft.lesson = "5"
        XCTAssertEqual(draft.proposedTitle, "Course - M01L05 - Before")
        draft.title = " \n"
        XCTAssertNil(draft.proposedTitle)
    }

    func testPlainNestedTitleEditsOnlyLeaf() throws {
        let folder = try XCTUnwrap(ProjectFolderPath(["Clients", "Acme"]))
        var draft = ProjectRenameDraft(.init(original: "Clients - Acme - Review",
                                            resolved: .init(folder: folder, code: nil, title: "Review")))
        XCTAssertFalse(draft.hasLesson)
        draft.title = "Final review"
        XCTAssertEqual(draft.proposedTitle, "Clients - Acme - Final review")
    }

    func testLooseTitleKeepsHyphens() {
        let name = "Product demo - v2"
        let draft = ProjectRenameDraft(.init(original: name, resolved: .init(folder: nil, code: nil, title: name)))
        XCTAssertEqual(draft.proposedTitle, name)
    }
}
