import Foundation
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class AccessControllerTests: XCTestCase {
    func testEveryFeatureIsFreeWithoutActivation() {
        let access = AccessController(defaults: temporaryDefaults())

        XCTAssertTrue(access.canRenderExport)
        XCTAssertTrue(access.canUseIPhoneCamera)
        XCTAssertTrue(access.canUse4KExport)
        XCTAssertTrue(access.canUse60FPSExport)
        XCTAssertEqual(access.accessLabel, "Free")
        XCTAssertTrue(access.accessMessage.isEmpty)
    }

    func testLegacyLicenseAndExportAllowanceCannotRestrictFeatures() {
        let defaults = temporaryDefaults()
        defaults.set(1_000, forKey: "access.usedFreeExports")
        defaults.set("expired-key", forKey: "access.blitzRecorderLicenseKey")
        defaults.set(Data("invalid-counter".utf8), forKey: "access.usedFreeExportsEnvelope")

        let access = AccessController(defaults: defaults)

        XCTAssertTrue(access.canRenderExport)
        XCTAssertTrue(access.canUseIPhoneCamera)
        XCTAssertTrue(access.canUse4KExport)
        XCTAssertTrue(access.canUse60FPSExport)
        XCTAssertTrue(access.accessMessage.isEmpty)
    }

    func testLegacyActivationLinkExplainsThatActivationIsUnnecessary() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)

        access.handleBlitzRecorderURL(URL(string: "blitzrecorder://activate?license_key=old-key")!)

        XCTAssertEqual(access.accessMessage, "All features are free. No account or license key is needed.")
        XCTAssertNil(defaults.string(forKey: "access.blitzRecorderLicenseKey"))
        XCTAssertTrue(access.canUse4KExport)
    }

    private func temporaryDefaults() -> UserDefaults {
        let name = "dev.blitzreels.blitzrecorder.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }
}
