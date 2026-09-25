import Foundation
import XCTest
@testable import BlitzRecorderApp

final class LivePreviewPreferenceTests: XCTestCase {
    func testPreviewStartsEnabledAndOffChoicePersists() {
        let suiteName = "LivePreviewPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preference = LivePreviewPreference(defaults: defaults)
        XCTAssertTrue(preference.isEnabled)

        preference.setEnabled(false)
        XCTAssertFalse(LivePreviewPreference(defaults: defaults).isEnabled)

        preference.setEnabled(true)
        XCTAssertTrue(LivePreviewPreference(defaults: defaults).isEnabled)
    }
}
