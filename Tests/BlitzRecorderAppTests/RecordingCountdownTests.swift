import XCTest
@testable import BlitzRecorderApp

final class RecordingCountdownTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "RecordingCountdownTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDefaultsToThreeSeconds() throws {
        XCTAssertEqual(RecordingCountdownPreference(defaults: try makeDefaults()).seconds, 3)
    }

    func testStoresSupportedValuesIncludingOff() throws {
        let preference = RecordingCountdownPreference(defaults: try makeDefaults())
        preference.setSeconds(0)
        XCTAssertEqual(preference.seconds, 0)
        preference.setSeconds(5)
        XCTAssertEqual(preference.seconds, 5)
    }

    func testRejectsUnsupportedValues() throws {
        let defaults = try makeDefaults()
        defaults.set(42, forKey: RecordingCountdownPreference.key)
        XCTAssertEqual(RecordingCountdownPreference(defaults: defaults).seconds, 3)
        RecordingCountdownPreference(defaults: defaults).setSeconds(9)
        XCTAssertEqual(RecordingCountdownPreference(defaults: defaults).seconds, 3)
    }

    @MainActor
    func testCancelClearsCountdown() throws {
        let defaults = try makeDefaults()
        let coordinator = RecorderCoordinator(accessController: AccessController(defaults: defaults), defaults: defaults)
        let vm = RecorderViewModel(coordinator: coordinator, previewStage: PreviewStageView())
        defer { vm.prepareForWindowClose() }
        vm.countdownRemaining = 2
        vm.primaryAction()
        XCTAssertNil(vm.countdownRemaining)
        XCTAssertEqual(vm.state, .idle)
    }
}
