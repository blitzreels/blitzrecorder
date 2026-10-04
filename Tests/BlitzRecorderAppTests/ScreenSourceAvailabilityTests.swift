import XCTest
@testable import BlitzRecorderApp

@MainActor
final class ScreenSourceAvailabilityTests: XCTestCase {
    func testMinimizedWindowIsPresentButClosedAndReusedWindowIDsAreNot() {
        let binding = source()
        let minimized: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 42),
            kCGWindowOwnerPID as String: NSNumber(value: 123),
            kCGWindowIsOnscreen as String: false
        ]
        XCTAssertTrue(ScreenSourceWindowPresence(binding: binding, windows: [minimized]).isPresent)
        XCTAssertFalse(ScreenSourceWindowPresence(binding: binding, windows: []).isPresent)
        var reused = minimized
        reused[kCGWindowOwnerPID as String] = NSNumber(value: 456)
        XCTAssertFalse(ScreenSourceWindowPresence(binding: binding, windows: [reused]).isPresent)
    }

    func testMissingWindowNoticeIsRedDuringRecordingAndClearsForNewSelection() throws {
        let suite = "ScreenSourceAvailabilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        vm.settings.enabledSources = [.screen]
        vm.settings.screenSourceBinding = source()
        vm.unavailableScreenSource = source()
        vm.state = .recording
        let notice = try XCTUnwrap(vm.sourceReadinessNotice(.screen))
        XCTAssertEqual(notice.title, "Window unavailable")
        XCTAssertEqual(notice.severity, .error)
        XCTAssertEqual(notice.action, .chooseScreen)
        vm.resolveSourceReadiness(.chooseScreen)
        XCTAssertTrue(vm.showsScreenSourcePicker)
        vm.settings.screenSourceBinding = .display(id: "5")
        XCTAssertNil(vm.unavailableScreenSourceNotice)
    }

    private func source() -> ScreenSourceBinding {
        .init(kind: .window, displayID: nil, bundleIdentifier: "example.fixture", applicationName: "Fixture",
              processID: 123, windowID: 42, windowTitle: "Document")
    }
}
