import Foundation
import XCTest
@testable import BlitzRecorderApp

final class RecorderUICaptureTests: XCTestCase {
    func testRecorderUIIsExcludedByDefaultAndPreferenceRoundTrips() {
        let name = "RecorderUICaptureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(RecordingSettingsStore.load(defaults: defaults).includesRecorderUI)
        var settings = RecordingSettings()
        for included in [true, false] {
            settings.includesRecorderUI = included
            RecordingSettingsStore.save(settings, defaults: defaults)
            XCTAssertEqual(RecordingSettingsStore.load(defaults: defaults).includesRecorderUI, included)
        }
    }

    func testCaptureAndPickersExcludeOnlyTheRecorderUntilEnabled() {
        for included in [false, true] {
            let policy = RecorderUICapturePolicy(includesRecorderUI: included, ownProcessID: 42)
            XCTAssertEqual(policy.excludes(processID: 42), !included)
            XCTAssertFalse(policy.excludes(processID: 43))
            XCTAssertFalse(policy.excludes(processID: nil))
            XCTAssertEqual(policy.excludedBundleIDs("test.recorder"), included ? [] : ["test.recorder"])
            XCTAssertEqual(policy.excludedBundleIDs(nil), [])
        }
    }

    @MainActor
    func testPreferenceRefreshesCaptureAndDisablingClearsRecorderWindowSelection() {
        let name = "RecorderUICaptureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let studio = RecorderStudioConfiguration(defaults: defaults)
        var refreshes = 0
        studio.onScreenCaptureConfigurationChanged = { refreshes += 1 }
        studio.setRecorderUIIncluded(true)
        XCTAssertTrue(studio.settings.includesRecorderUI)
        XCTAssertEqual(refreshes, 1)
        studio.settings.screenSourceBinding = .init(
            kind: .window, displayID: "42", bundleIdentifier: Bundle.main.bundleIdentifier,
            applicationName: "BlitzRecorder", processID: getpid(), windowID: 7, windowTitle: "BlitzRecorder")
        studio.setRecorderUIIncluded(false)
        XCTAssertFalse(studio.settings.includesRecorderUI)
        XCTAssertEqual(studio.settings.screenSourceBinding?.kind, .display)
        XCTAssertEqual(studio.settings.screenSourceBinding?.displayID, "42")
        XCTAssertFalse(studio.settings.usesPickedScreenContent)
        XCTAssertEqual(refreshes, 2)
    }

    @MainActor
    func testPreferenceCannotChangeDuringRecordingOrFinalization() {
        let name = "RecorderUICaptureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let studio = RecorderStudioConfiguration(defaults: defaults)
        for state in [RecordingState.starting, .recording, .paused, .finishing] {
            studio.recordingState = { state }
            studio.setRecorderUIIncluded(true)
            XCTAssertFalse(studio.settings.includesRecorderUI)
        }
    }
}
