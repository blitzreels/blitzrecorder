@testable import BlitzRecorderApp
import XCTest

final class ScreenPreviewLifecycleTests: XCTestCase {
    func testHiddenConfiguredScreenPreservesRunningPreviewStream() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.hiddenSources = [.screen]

        let action = ScreenPreviewLifecycle.action(
            settings: settings,
            previewIsRunning: true,
            preservedSelectionRevision: nil,
            currentSelectionRevision: 4
        )

        XCTAssertEqual(action, .preserveHidden)
    }

    func testRemovedScreenRestartsSoCallerCanStopPreviewStream() {
        var settings = RecordingSettings()
        settings.enabledSources = [.camera]
        settings.hiddenSources = []

        let action = ScreenPreviewLifecycle.action(
            settings: settings,
            previewIsRunning: true,
            preservedSelectionRevision: 4,
            currentSelectionRevision: 4
        )

        XCTAssertEqual(action, .restart)
    }

    func testReenabledScreenReusesPreservedPreviewWhenSelectionDidNotChange() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.hiddenSources = [.camera]

        let action = ScreenPreviewLifecycle.action(
            settings: settings,
            previewIsRunning: true,
            preservedSelectionRevision: 4,
            currentSelectionRevision: 4
        )

        XCTAssertEqual(action, .reusePreserved)
    }

    func testReenabledScreenRestartsWhenSelectionChangedWhileHidden() {
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.hiddenSources = [.camera]

        let action = ScreenPreviewLifecycle.action(
            settings: settings,
            previewIsRunning: true,
            preservedSelectionRevision: 4,
            currentSelectionRevision: 5
        )

        XCTAssertEqual(action, .restart)
    }
}
