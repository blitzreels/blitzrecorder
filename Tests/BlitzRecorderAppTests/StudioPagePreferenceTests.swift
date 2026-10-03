@testable import BlitzRecorderApp
import XCTest

final class StudioPagePreferenceTests: XCTestCase {
    func testLastPageRoundTripsWithEditedProject() throws {
        let suite = "StudioPagePreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = StudioPagePreference(defaults: defaults)
        XCTAssertNil(preference.load())

        let projectID = UUID()
        preference.save(.init(page: .edit, projectID: projectID))
        XCTAssertEqual(preference.load(), .init(page: .edit, projectID: projectID))

        preference.save(.init(page: .record, projectID: nil))
        XCTAssertEqual(preference.load(), .init(page: .record, projectID: nil))
    }
}
