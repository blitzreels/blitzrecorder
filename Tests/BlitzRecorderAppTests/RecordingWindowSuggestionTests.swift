import XCTest
@testable import BlitzRecorderApp

@MainActor
final class RecordingWindowSuggestionTests: XCTestCase {
    func testTemporaryOverlayCannotBecomeTheRecordingSource() {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: Int32(42),
            kCGWindowOwnerName as String: "Fixture",
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: CGRect(x: 214, y: 49, width: 66, height: 20).dictionaryRepresentation
        ]
        XCTAssertFalse(RecordingSourceSuggestion.isRecordableWindow(info))
        info[kCGWindowBounds as String] = CGRect(x: 0, y: 0, width: 900, height: 600).dictionaryRepresentation
        XCTAssertTrue(RecordingSourceSuggestion.isRecordableWindow(info))
        info[kCGWindowAlpha as String] = 0.0
        XCTAssertFalse(RecordingSourceSuggestion.isRecordableWindow(info))
    }

    func testFollowOffWaitsForAcceptanceAndDismissalSurvivesTitleChanges() {
        withViewModel { vm in
            vm.followsActiveWindow = false
            let original = vm.settings.screenSourceBinding
            var candidate = self.window(2)
            vm.updateScreenSuggestion(candidate)
            XCTAssertNil(vm.suggestedScreenSource)
            vm.updateScreenSuggestion(candidate)
            XCTAssertEqual(vm.suggestedScreenSource, candidate)
            XCTAssertEqual(vm.settings.screenSourceBinding, original)
            vm.dismissScreenSuggestion()
            candidate.windowTitle = "A different tab"
            vm.updateScreenSuggestion(candidate)
            XCTAssertNil(vm.suggestedScreenSource)
            XCTAssertEqual(vm.settings.screenSourceBinding, original)
            vm.updateScreenSuggestion(original)
            vm.updateScreenSuggestion(candidate)
            vm.updateScreenSuggestion(candidate)
            XCTAssertEqual(vm.suggestedScreenSource, candidate)
            vm.acceptScreenSuggestion()
            XCTAssertEqual(vm.settings.screenSourceBinding, candidate)
            XCTAssertNil(vm.suggestedScreenSource)
        }
    }

    func testFollowOnRequiresConsecutiveObservationsAndResetsOnMissingWindow() {
        withViewModel { vm in
            vm.followsActiveWindow = true
            let original = vm.settings.screenSourceBinding
            let candidate = self.window(2)
            vm.updateScreenSuggestion(candidate)
            vm.updateScreenSuggestion(nil)
            vm.updateScreenSuggestion(candidate)
            XCTAssertEqual(vm.settings.screenSourceBinding, original)
            vm.updateScreenSuggestion(candidate)
            XCTAssertEqual(vm.settings.screenSourceBinding, candidate)
            XCTAssertNil(vm.suggestedScreenSource)
        }
    }

    func testTurningFollowOffClearsPendingAutomaticSwitch() {
        withViewModel { vm in
            vm.followsActiveWindow = true
            let original = vm.settings.screenSourceBinding
            let candidate = self.window(2)
            vm.updateScreenSuggestion(candidate)
            vm.followsActiveWindow = false
            vm.updateScreenSuggestion(candidate)
            vm.updateScreenSuggestion(candidate)
            XCTAssertEqual(vm.settings.screenSourceBinding, original)
            XCTAssertEqual(vm.suggestedScreenSource, candidate)
        }
    }

    func testNewCandidateReplacesDismissedPromptAndPauseClearsIt() {
        withViewModel { vm in
            vm.followsActiveWindow = false
            vm.updateScreenSuggestion(self.window(2))
            vm.updateScreenSuggestion(self.window(2))
            vm.dismissScreenSuggestion()
            vm.updateScreenSuggestion(self.window(3))
            XCTAssertNil(vm.suggestedScreenSource)
            vm.updateScreenSuggestion(self.window(3))
            XCTAssertEqual(vm.suggestedScreenSource, self.window(3))
            vm.state = .paused
            vm.refreshScreenSuggestion()
            XCTAssertNil(vm.suggestedScreenSource)
            XCTAssertNil(vm.pendingFollowKey)
            XCTAssertNil(vm.dismissedScreenSuggestion)
        }
    }

    private func withViewModel(_ body: (RecorderViewModel) -> Void) {
        let suite = "RecordingWindowSuggestionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let previousFollow = UserDefaults.standard.object(forKey: FollowActiveWindowPreference.key)
        defer {
            defaults.removePersistentDomain(forName: suite)
            if let previousFollow {
                UserDefaults.standard.set(previousFollow, forKey: FollowActiveWindowPreference.key)
            } else {
                UserDefaults.standard.removeObject(forKey: FollowActiveWindowPreference.key)
            }
        }
        var settings = RecordingSettings()
        settings.enabledSources = [.screen]
        settings.screenSourceBinding = window(1)
        RecordingSettingsStore.save(settings, defaults: defaults)
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer {
            vm.autoSwitchNoticeTask?.cancel()
            vm.prepareForWindowClose()
        }
        vm.state = .recording
        body(vm)
    }

    private func window(_ id: UInt32) -> ScreenSourceBinding {
        .init(kind: .window, displayID: nil, bundleIdentifier: "example.suggestion",
              applicationName: "Fixture", processID: -1, windowID: id, windowTitle: "Window \(id)")
    }
}
