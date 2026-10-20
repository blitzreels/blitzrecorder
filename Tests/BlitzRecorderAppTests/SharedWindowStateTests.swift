import XCTest
@testable import BlitzRecorderApp

/// The main window and the editor window share one coordinator; these pin what they must agree on.
@MainActor
final class SharedWindowStateTests: XCTestCase {
    private var root: URL!
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SharedWindowState-\(UUID().uuidString)")
        defaultsSuite = "SharedWindowStateTests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
    }

    private func makeWindows() throws -> (main: RecorderViewModel, editor: RecorderViewModel) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let main = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        let editor = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        for vm in [main, editor] {
            vm.transcriptionController.isAutomaticEnabled = false
            vm.settings.outputDirectory = root
            vm.settings.projectLibrary = .init(url: root, bookmarkData: nil)
            vm.settings.savesSourceFiles = true
        }
        return (main, editor)
    }

    func testANewRecordingShowsUpInBothWindowsAfterOneRefresh() throws {
        let windows = try makeWindows()
        let take = try TakeFileStore().createTake(settings: windows.main.settings)

        windows.main.refreshRecentProjects()

        XCTAssertEqual(windows.editor.recentProjects.map(\.projectPath), [take.projectURL.path])
    }

    func testFinishedTranscriptIsHandledOnceAndStillHandledAfterAWindowCloses() throws {
        let controller = LocalTranscriptionController()
        var handledBy: [String] = []
        var first: NSObject? = NSObject()
        let second = NSObject()
        controller.addCompletionHandler(.init(owner: first) { _ in handledBy.append("first") })
        controller.addCompletionHandler(.init(owner: second) { _ in handledBy.append("second") })
        let completion = CompletedTranscription(
            source: .project(root.appendingPathComponent("project.blitzrecorder.json")),
            transcript: RecordingTranscript(version: 1, id: UUID(), mediaPath: root.path, generatedAt: Date(),
                duration: 1, confidence: 1, text: "Hello", suggestedTitle: nil, speakers: [], segments: [])
        )

        controller.deliverCompletion(completion)
        first = nil
        controller.deliverCompletion(completion)

        XCTAssertEqual(handledBy, ["first", "second"])
    }

    func testMissingPreferredMicIsNamedAndRecordingWithAnotherMicKeepsThePreference() throws {
        let vm = try makeWindows().main
        vm.settings.enabledSources = [.microphone]
        vm.settings.selectedMicrophoneID = "rodecaster"
        vm.settings.selectedMicrophoneName = "RODECaster Pro II Chat"
        vm.availableMicrophones = [SourceOption(id: "c920", name: "HD Pro Webcam C920")]

        let missing = try XCTUnwrap(vm.missingPreferredMicrophone)
        XCTAssertEqual(missing.preferredName, "RODECaster Pro II Chat")
        XCTAssertEqual(vm.sourceReadinessNotice(.microphone)?.title, "Preferred mic not connected")

        vm.session.pendingMicrophoneFallback = missing
        vm.recordWithFallbackMicrophone()
        XCTAssertNil(vm.session.pendingMicrophoneFallback)
        XCTAssertEqual(vm.settings.selectedMicrophoneID, "rodecaster")

        vm.availableMicrophones.append(SourceOption(id: "rodecaster", name: "RODECaster Pro II Chat"))
        XCTAssertNil(vm.missingPreferredMicrophone)
        XCTAssertNil(vm.sourceReadinessNotice(.microphone))
    }

    func testShowInLibraryOpensTheLibraryOnTheJustRecordedTake() throws {
        let vm = try makeWindows().main
        let take = try TakeFileStore().createTake(settings: vm.settings)
        vm.refreshRecentProjects()
        vm.lastExportedSourceTakeURL = take.scratchDirectory
        vm.projectLibraryNavigation.searchText = "something else"
        vm.projectLibraryNavigation.section = .shared

        vm.showLastRecordingInLibrary()

        let entry = try XCTUnwrap(vm.recentProjects.first)
        XCTAssertEqual(vm.studioMode, .projects)
        XCTAssertEqual(vm.projectLibraryNavigation.section, .recordings)
        XCTAssertEqual(vm.projectLibraryNavigation.searchText, "")
        XCTAssertEqual(vm.projectLibraryNavigation.selectedProjectIDs, [entry.id])
    }
}
