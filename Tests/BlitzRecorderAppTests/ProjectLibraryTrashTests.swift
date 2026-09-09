import Foundation
import XCTest

@testable import BlitzRecorderApp

final class ProjectLibraryTrashTests: XCTestCase {
    func testSelectionMovesToNextNeighborThenPreviousNeighbor() {
        let ids = (0..<5).map { _ in UUID() }
        var navigation = ProjectLibraryNavigationState(selectedProjectIDs: [ids[2], ids[3]])
        navigation.reconcileAfterRemoval(
            .init(
                previousOrder: ids, removedIDs: [ids[2], ids[3]], availableIDs: [ids[0], ids[1], ids[4]]
            ))
        XCTAssertEqual(navigation.selectedProjectIDs, [ids[4]])
        navigation.reconcileAfterRemoval(
            .init(
                previousOrder: [ids[0], ids[1], ids[4]], removedIDs: [ids[4]], availableIDs: [ids[0], ids[1]]
            ))
        XCTAssertEqual(navigation.selectedProjectIDs, [ids[1]])
    }

    func testFailedAndUnrelatedSelectionsArePreserved() {
        let ids = (0..<3).map { _ in UUID() }
        var navigation = ProjectLibraryNavigationState(selectedProjectIDs: [ids[0], ids[1]])
        navigation.reconcileAfterRemoval(
            .init(previousOrder: ids, removedIDs: [ids[0]], availableIDs: [ids[1], ids[2]]))
        XCTAssertEqual(navigation.selectedProjectIDs, [ids[1]])
        navigation.reconcileAfterRemoval(.init(previousOrder: ids, removedIDs: [ids[2]], availableIDs: [ids[1]]))
        XCTAssertEqual(navigation.selectedProjectIDs, [ids[1]])
        navigation.reconcileAfterRemoval(.init(previousOrder: [ids[1]], removedIDs: [ids[1]], availableIDs: []))
        XCTAssertTrue(navigation.selectedProjectIDs.isEmpty)
    }

    @MainActor
    func testBatchContinuesAfterFailureAndOnlyRestoresSuccessfulItems() async {
        let projects = (0..<3).map { Self.entry("Project \($0)") }
        var attempted: [UUID] = []
        var restored: [UUID] = []
        let controller = ProjectLibraryTrashController(
            operations: .init(
                trash: { request in
                    attempted.append(request.project.id)
                    if request.project.id == projects[1].id { throw CocoaError(.fileWriteNoPermission) }
                    return .init(project: request.project, trashedDirectory: URL(fileURLWithPath: "/unused"))
                },
                restore: { request in restored.append(request.receipt.project.id) }
            ))
        let result = await controller.trash(.init(projects: projects + [projects[0]], settings: RecordingSettings()))
        XCTAssertEqual(attempted, projects.map(\.id))
        XCTAssertEqual(result.completedIDs, [projects[0].id, projects[2].id])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(controller.restorableCount, 2)
        let recovery = await controller.restoreLastBatch()
        XCTAssertEqual(Set(restored), result.completedIDs)
        XCTAssertEqual(recovery.completedIDs, result.completedIDs)
        XCTAssertFalse(controller.canRestore)
    }

    @MainActor
    func testFailedRestorationRemainsAvailableForRetry() async {
        let project = Self.entry("Retry restoration")
        var shouldFail = true
        let controller = ProjectLibraryTrashController(
            operations: .init(
                trash: { .init(project: $0.project, trashedDirectory: URL(fileURLWithPath: "/unused")) },
                restore: { _ in if shouldFail { throw CocoaError(.fileWriteNoPermission) } }
            ))
        _ = await controller.trash(.init(projects: [project], settings: RecordingSettings()))
        let first = await controller.restoreLastBatch()
        XCTAssertEqual(first.failures.count, 1)
        XCTAssertTrue(controller.canRestore)
        shouldFail = false
        let retry = await controller.restoreLastBatch()
        XCTAssertEqual(retry.completedIDs, [project.id])
        XCTAssertFalse(controller.isWorking)
        XCTAssertFalse(controller.canRestore)
    }

    @MainActor
    func testProgressIsVisibleWhileIOWaitsAndDuplicateRequestsAreIgnored() async {
        let project = Self.entry("Busy project")
        let entered = expectation(description: "Trash operation started")
        var resume: CheckedContinuation<Void, Never>?
        let controller = ProjectLibraryTrashController(
            operations: .init(
                trash: { request in
                    await withCheckedContinuation { continuation in
                        resume = continuation
                        entered.fulfill()
                    }
                    return .init(project: request.project, trashedDirectory: URL(fileURLWithPath: "/unused"))
                },
                restore: { _ in }
            ))
        let request = ProjectLibraryTrashController.Request(projects: [project], settings: RecordingSettings())
        let task = Task { await controller.trash(request) }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(controller.isWorking)
        XCTAssertEqual(controller.status, "Moving to Trash… 1 of 1")
        let duplicate = await controller.trash(request)
        XCTAssertTrue(duplicate.completedIDs.isEmpty)
        resume?.resume()
        let result = await task.value
        XCTAssertEqual(result.completedIDs, [project.id])
        XCTAssertFalse(controller.isWorking)
    }

    func testTrashAndRestorePreserveSourcesAndExternalExport() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let contents = Data("source media".utf8)
        try contents.write(to: fixture.take.screenURL)
        let export = fixture.settings.outputDirectory.appendingPathComponent("finished.mov")
        try Data("export".utf8).write(to: export)
        let receipt = try XCTUnwrap(
            fixture.store.deleteProject(
                .init(
                    project: fixture.project, settings: fixture.settings, disposition: .trash
                )))
        defer { try? fixture.store.restoreProjectFromTrash(.init(receipt: receipt, settings: fixture.settings)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.take.scratchDirectory.path))
        XCTAssertTrue(fixture.store.loadProjectHistory(settings: fixture.settings).entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        try fixture.store.restoreProjectFromTrash(.init(receipt: receipt, settings: fixture.settings))
        XCTAssertEqual(try Data(contentsOf: fixture.take.screenURL), contents)
        XCTAssertEqual(
            fixture.store.loadProjectHistory(settings: fixture.settings).entries.map(\.id), [fixture.project.id])
        XCTAssertEqual(try fixture.store.loadRecordingProject(at: fixture.take.projectURL).id, fixture.project.id)
    }

    func testRestorationDoesNotOverwriteAnExistingFolder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let receipt = try XCTUnwrap(
            fixture.store.deleteProject(
                .init(
                    project: fixture.project, settings: fixture.settings, disposition: .trash
                )))
        let original = fixture.take.scratchDirectory
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let marker = original.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)
        XCTAssertThrowsError(
            try fixture.store.restoreProjectFromTrash(.init(receipt: receipt, settings: fixture.settings)))
        XCTAssertEqual(try String(contentsOf: marker), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.trashedDirectory.path))
        try FileManager.default.removeItem(at: original)
        try fixture.store.restoreProjectFromTrash(.init(receipt: receipt, settings: fixture.settings))
    }

    func testHistoryWriteFailurePutsTheSourceFolderBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let history = fixture.store.projectHistoryURL(for: fixture.settings)
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try fixture.store.deleteProject(
                .init(
                    project: fixture.project, settings: fixture.settings, disposition: .trash
                )))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.take.projectURL.path))
    }

    func testMismatchedProjectIdentityCannotDeleteTheFolder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wrong = RecordingProjectHistory.Entry(
            id: UUID(), title: "Different project", projectPath: fixture.project.projectPath,
            takeDirectoryPath: fixture.project.takeDirectoryPath, finalVideoPath: nil,
            createdAt: nil, updatedAt: Date(), exports: nil
        )
        XCTAssertThrowsError(
            try fixture.store.deleteProject(.init(project: wrong, settings: fixture.settings, disposition: .trash)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.take.projectURL.path))
    }

    func testSymlinkCannotTargetFilesOutsideTheSourceFolder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.settings.outputDirectory.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let marker = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)
        let link = fixture.take.scratchDirectory.deletingLastPathComponent().appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let project = RecordingProjectHistory.Entry(
            id: UUID(), title: "Linked project",
            projectPath: link.appendingPathComponent("project.blitzrecorder.json").path,
            takeDirectoryPath: link.path, finalVideoPath: nil, createdAt: nil, updatedAt: Date(), exports: nil
        )
        XCTAssertThrowsError(
            try fixture.store.deleteProject(.init(project: project, settings: fixture.settings, disposition: .trash)))
        XCTAssertEqual(try String(contentsOf: marker), "keep")
    }

    @MainActor
    func testDeletingTheLastProjectKeepsRecoveryVisibleAndRestoresTheLibrary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let suite = "ProjectLibraryTrashTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(
            accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        vm.settings = fixture.settings
        vm.openProject(fixture.project)
        vm.projectLibraryNavigation.selectedProjectIDs = [fixture.project.id]
        await vm.deleteProjects([fixture.project])
        XCTAssertEqual(vm.studioMode, .projects)
        XCTAssertTrue(vm.recentProjects.isEmpty)
        XCTAssertTrue(vm.canShowProjects)
        XCTAssertNil(vm.lastExportedProject)
        await vm.restoreTrashedProjects()
        XCTAssertEqual(vm.recentProjects.map(\.id), [fixture.project.id])
        XCTAssertEqual(vm.projectLibraryNavigation.selectedProjectIDs, [fixture.project.id])
    }

    private static func entry(_ title: String) -> RecordingProjectHistory.Entry {
        let id = UUID()
        return .init(
            id: id, title: title, projectPath: "/unused/\(id)/project.blitzrecorder.json",
            takeDirectoryPath: "/unused/\(id)", finalVideoPath: nil, createdAt: nil, updatedAt: Date(), exports: nil
        )
    }

    private struct Fixture {
        let store = TakeFileStore()
        let settings: RecordingSettings
        let take: RecordingTake
        let project: RecordingProjectHistory.Entry

        init() throws {
            var settings = RecordingSettings()
            settings.outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.settings = settings
            take = try store.createTake(settings: settings)
            project = try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first)
        }

        func remove() {
            try? FileManager.default.removeItem(at: settings.outputDirectory)
        }
    }
}
