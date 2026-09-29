import Foundation
import XCTest
@testable import BlitzRecorderApp

final class RecordingStorageTests: XCTestCase {
    @MainActor
    func testSourceFolderChoicePersistsKeepsPreviousProjectsAndLeavesExportFolderAlone() throws {
        let fixture = try fixture()
        let suite = "BlitzRecorder.StorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var initial = RecordingSettings()
        initial.outputDirectory = fixture.exports
        initial.projectLibrary = .init(url: fixture.library, bookmarkData: nil)
        RecordingSettingsStore.save(initial, defaults: defaults)
        let store = TakeFileStore()
        let first = try store.createTake(settings: initial)
        let original = try Data(contentsOf: first.projectURL)
        let studio = RecorderStudioConfiguration(defaults: defaults)
        studio.setSourceDirectory(fixture.other)
        let reloaded = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertEqual(reloaded.sourceStorage.url.standardizedFileURL, fixture.other.standardizedFileURL)
        XCTAssertEqual(reloaded.outputDirectory, fixture.exports)
        let next = try store.createTake(settings: reloaded)
        XCTAssertEqual(next.scratchDirectory.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath(),
                       fixture.other.resolvingSymlinksInPath())
        XCTAssertEqual(next.finalVideoURL.deletingLastPathComponent(), fixture.exports)
        XCTAssertEqual(Set(store.loadProjectHistory(settings: reloaded).entries.map(\.projectPath)),
                       Set([first.projectURL.path, next.projectURL.path]))
        XCTAssertEqual(try Data(contentsOf: first.projectURL), original)
        studio.setSourceDirectory(fixture.library)
        studio.setSourceDirectory(fixture.library)
        let switchedBack = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertEqual(switchedBack.projectLibraries.count, 2)
        XCTAssertEqual(store.loadProjectHistory(settings: switchedBack).entries.count, 2)
    }

    @MainActor
    func testSourceFolderCannotChangeDuringRecording() throws {
        let fixture = try fixture()
        let suite = "BlitzRecorder.StorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(fixture.library.path, forKey: "recording.outputDirectoryPath")
        let studio = RecorderStudioConfiguration(defaults: defaults)
        studio.recordingState = { .recording }
        studio.setSourceDirectory(fixture.other)
        XCTAssertEqual(studio.settings.sourceStorage.url, fixture.library)
        XCTAssertEqual(RecordingSettingsStore.load(defaults: defaults).sourceStorage.url, fixture.library)
    }

    func testPendingCameraImportsRemainRecoverableAfterSwitchingSourceFolder() throws {
        let fixture = try fixture()
        var initial = RecordingSettings()
        initial.outputDirectory = fixture.library
        let take = try TakeFileStore().createTake(settings: initial)
        let store = RemoteCameraPendingImportStore()
        let id = UUID()
        store.upsert(.init(takeID: id, serviceID: nil, scratchDirectory: take.scratchDirectory,
                           destinationURL: take.cameraURL, createdAt: Date(), expectedByteCount: nil), settings: initial)
        var changed = initial
        changed.projectLibrary = .init(url: fixture.other, bookmarkData: nil)
        changed.additionalProjectLibraries = [initial.sourceStorage]
        XCTAssertEqual(store.all(settings: changed).map(\.takeID), [id])
        store.updatePhase(takeID: id, phase: .ready, settings: changed)
        store.updateExpectedByteCount(takeID: id, expectedByteCount: 42, settings: changed)
        let pending = try XCTUnwrap(store.all(settings: initial).first)
        XCTAssertEqual(pending.phase, .ready)
        XCTAssertEqual(pending.expectedByteCount, 42)
        store.upsert(pending, settings: changed)
        XCTAssertEqual(store.all(settings: changed).count, 1)
        store.remove(takeID: id, settings: changed)
        XCTAssertTrue(store.all(settings: changed).isEmpty)
        XCTAssertTrue(store.all(settings: initial).isEmpty)
    }

    @MainActor
    func testChangingExportFolderPinsLegacyLibraryAcrossReopenAndFurtherChanges() throws {
        let fixture = try fixture()
        let suite = "BlitzRecorder.StorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(fixture.library.path, forKey: "recording.outputDirectoryPath")
        let studio = RecorderStudioConfiguration(defaults: defaults)
        XCTAssertNil(studio.settings.projectLibrary)
        studio.setOutputDirectory(fixture.exports)
        let reloaded = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertEqual(reloaded.outputDirectory.standardizedFileURL, fixture.exports.standardizedFileURL)
        XCTAssertEqual(reloaded.sourceStorage.url.standardizedFileURL, fixture.library.standardizedFileURL)
        studio.setOutputDirectory(fixture.other)
        XCTAssertEqual(RecordingSettingsStore.load(defaults: defaults).sourceStorage.url, fixture.library)
    }

    func testNewTakesKeepSourcesAndHistoryInLibraryWhileFinishedVideosUseNewFolder() throws {
        let fixture = try fixture()
        var settings = RecordingSettings()
        settings.outputDirectory = fixture.library
        let store = TakeFileStore()
        let first = try store.createTake(settings: settings)
        let original = try Data(contentsOf: first.projectURL)
        settings.projectLibrary = settings.sourceStorage
        settings.outputDirectory = fixture.exports
        let access = try store.prepareOutputDirectory(settings: settings)
        defer { access.stop() }
        let second = try store.createTake(settings: settings)
        XCTAssertEqual(second.scratchDirectory.deletingLastPathComponent(), first.scratchDirectory.deletingLastPathComponent())
        XCTAssertEqual(second.finalVideoURL.deletingLastPathComponent(), fixture.exports)
        XCTAssertEqual(store.loadProjectHistory(settings: settings).entries.count, 2)
        XCTAssertEqual(try Data(contentsOf: first.projectURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.exports.appendingPathComponent("BlitzRecorder Source Takes").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.exports.appendingPathComponent("BlitzRecorder Projects").path))
    }

    func testLinkedLibraryPersistsAndProjectEditsAndDeletionUseItsOwnIndex() throws {
        let fixture = try fixture()
        let store = TakeFileStore()
        var primary = RecordingSettings()
        primary.outputDirectory = fixture.library
        let first = try store.createTake(settings: primary)
        var secondary = RecordingSettings()
        secondary.outputDirectory = fixture.other
        let second = try store.createTake(settings: secondary)
        let primaryIndex = try Data(contentsOf: store.projectHistoryURL(for: primary))
        primary.projectLibrary = primary.sourceStorage
        primary.outputDirectory = fixture.exports
        primary.additionalProjectLibraries = [secondary.sourceStorage, secondary.sourceStorage]
        let suite = "BlitzRecorder.StorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecordingSettingsStore.save(primary, defaults: defaults)
        let reloaded = RecordingSettingsStore.load(defaults: defaults)
        XCTAssertEqual(reloaded.projectLibraries.count, 2)
        XCTAssertEqual(Set(store.loadProjectHistory(settings: reloaded).entries.map(\.projectPath)),
                       Set([first.projectURL.path, second.projectURL.path]))
        _ = try store.renameProject(.init(projectURL: second.projectURL, title: "Renamed linked project", settings: reloaded))
        XCTAssertEqual(try Data(contentsOf: store.projectHistoryURL(for: primary)), primaryIndex)
        let entry = try XCTUnwrap(store.loadProjectHistory(settings: secondary).entries.first)
        XCTAssertEqual(entry.title, "Renamed linked project")
        _ = try store.deleteProject(.init(project: entry, settings: reloaded, disposition: .permanent))
        XCTAssertEqual(store.loadProjectHistory(settings: reloaded).entries.map(\.projectPath), [first.projectURL.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.projectURL.path))
    }

    func testStaleDuplicateIndexCannotResurrectDeletedProject() throws {
        let fixture = try fixture()
        let store = TakeFileStore()
        var settings = RecordingSettings()
        settings.outputDirectory = fixture.library
        _ = try store.createTake(settings: settings)
        let entry = try XCTUnwrap(store.loadProjectHistory(settings: settings).entries.first)
        var other = RecordingSettings()
        other.outputDirectory = fixture.other
        let duplicateIndex = store.projectHistoryURL(for: other)
        try FileManager.default.createDirectory(at: duplicateIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: store.projectHistoryURL(for: settings)).write(to: duplicateIndex)
        settings.additionalProjectLibraries = [other.sourceStorage]
        XCTAssertEqual(store.loadProjectHistory(settings: settings).entries.count, 1)
        _ = try store.deleteProject(.init(project: entry, settings: settings, disposition: .permanent))
        XCTAssertTrue(store.loadProjectHistory(settings: settings).entries.isEmpty)
    }

    func testUnavailableLinkedLibraryDoesNotHidePrimaryProjects() throws {
        let fixture = try fixture()
        let store = TakeFileStore()
        var settings = RecordingSettings()
        settings.outputDirectory = fixture.library
        let take = try store.createTake(settings: settings)
        settings.additionalProjectLibraries = [.init(url: fixture.other.appendingPathComponent("offline"), bookmarkData: nil)]
        XCTAssertEqual(store.loadProjectHistory(settings: settings).entries.map(\.projectPath), [take.projectURL.path])
    }

    private struct Fixture {
        let library: URL
        let exports: URL
        let other: URL
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BlitzRecorderStorageTests-\(UUID().uuidString)")
        let result = Fixture(library: root.appendingPathComponent("Library", isDirectory: true),
                             exports: root.appendingPathComponent("Exports", isDirectory: true),
                             other: root.appendingPathComponent("Other", isDirectory: true))
        for url in [result.library, result.exports, result.other] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return result
    }
}
