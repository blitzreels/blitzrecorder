import Foundation
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class AccessControllerTests: XCTestCase {
    func testAccessIsFreeByDefault() {
        let access = AccessController(defaults: temporaryDefaults())

        XCTAssertFalse(access.isPro)
        XCTAssertTrue(access.canRenderExport)
        XCTAssertFalse(access.canUseIPhoneCamera)
        XCTAssertFalse(access.canUse4KExport)
        XCTAssertFalse(access.canUse60FPSExport)
        XCTAssertEqual(access.accessLabel, "Free")
        XCTAssertEqual(access.freeExportsRemaining, ProductConfiguration.freeExportLimit)
    }

    func testSuccessfulExportsDoNotConsumeAllowance() {
        let defaults = temporaryDefaults()
        let access = AccessController(defaults: defaults)

        for _ in 0..<(ProductConfiguration.freeExportLimit + 3) {
            access.recordSuccessfulExportIfNeeded()
        }

        XCTAssertTrue(access.canRenderExport)
        XCTAssertEqual(access.usedFreeExports, 0)
        XCTAssertNil(defaults.data(forKey: "access.usedFreeExportsEnvelope"))
    }

    func testLegacyExportCountsDoNotBlockRecording() {
        let defaults = temporaryDefaults()
        defaults.set(ProductConfiguration.freeExportLimit + 100, forKey: "access.usedFreeExports")

        let access = AccessController(defaults: defaults)

        XCTAssertTrue(access.canRenderExport)
        XCTAssertFalse(access.isPro)
        XCTAssertEqual(access.accessLabel, "Free")
    }

    func testFailedAppIntegrityDoesNotBlockFreeAccess() {
        let access = AccessController(
            defaults: temporaryDefaults(),
            appIntegrityChecker: StubAppIntegrityChecker(status: .failed("Signature mismatch."))
        )

        XCTAssertFalse(access.hasValidAppIntegrity)
        XCTAssertTrue(access.canRenderExport)
        XCTAssertFalse(access.isPro)
        XCTAssertEqual(access.accessLabel, "Free")
    }

    func testBlitzReelsEntitlementRefreshDoesNotGateAccessOrCallNetwork() async {
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "legacy-token")
        let checker = StubBlitzReelsEntitlementChecker(
            result: .success(.init(active: false, planName: nil))
        )
        let access = AccessController(
            defaults: temporaryDefaults(),
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlement()

        XCTAssertTrue(access.canRenderExport)
        XCTAssertFalse(access.hasBlitzReelsEntitlement)
        XCTAssertEqual(checker.requestedTokens, [])
        XCTAssertEqual(access.accessMessage, "BlitzRecorder has a free 1080p tier. Early Price unlocks iPhone camera, 4K, and 60 fps.")
    }

    func testValidLicenseActivatesPaidFeatures() async {
        let keyStore = InMemoryLicenseKeyStore()
        let validator = StubLicenseValidator(
            result: .success(
                BlitzRecorderLicenseValidationResponse(
                    ok: true,
                    status: "active",
                    reason: nil,
                    payload: .init(licenseId: "br_test", email: "buyer@example.com", kind: "early_lifetime")
                )
            )
        )
        let access = AccessController(
            defaults: temporaryDefaults(),
            blitzRecorderLicenseKeyStore: keyStore,
            blitzRecorderLicenseValidator: validator
        )

        await access.activateLicenseKey(" BRL1_test ")

        XCTAssertTrue(access.isPro)
        XCTAssertTrue(access.canUseIPhoneCamera)
        XCTAssertTrue(access.canUse4KExport)
        XCTAssertTrue(access.canUse60FPSExport)
        XCTAssertEqual(access.accessLabel, "Early Price license active")
        XCTAssertEqual(access.licenseEmail, "buyer@example.com")
        XCTAssertEqual(access.licenseID, "br_test")
        XCTAssertEqual(access.accessMessage, "License activated for buyer@example.com.")
        XCTAssertEqual(keyStore.licenseKey, "BRL1_test")
    }

    func testLicenseActivationShowsValidatingStateBeforeNetworkReturns() async {
        let validator = StubLicenseValidator(
            result: .success(
                BlitzRecorderLicenseValidationResponse(
                    ok: true,
                    status: "active",
                    reason: nil,
                    payload: .init(licenseId: "br_test", email: "buyer@example.com", kind: "early_lifetime")
                )
            ),
            delayNanoseconds: 50_000_000
        )
        let access = AccessController(
            defaults: temporaryDefaults(),
            blitzRecorderLicenseKeyStore: InMemoryLicenseKeyStore(),
            blitzRecorderLicenseValidator: validator
        )

        let activation = Task {
            await access.activateLicenseKey("BRL1_test")
        }
        for _ in 0..<50 {
            if access.isValidatingLicense { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertTrue(access.isValidatingLicense)
        XCTAssertEqual(access.accessMessage, "Activating license...")

        await activation.value
        XCTAssertFalse(access.isValidatingLicense)
        XCTAssertTrue(access.hasActiveLicense)
    }

    func testInvalidLicenseDoesNotActivatePaidFeatures() async {
        let keyStore = InMemoryLicenseKeyStore()
        let validator = StubLicenseValidator(
            result: .success(
                BlitzRecorderLicenseValidationResponse(
                    ok: false,
                    status: "invalid",
                    reason: "License signature is invalid",
                    payload: nil
                )
            )
        )
        let access = AccessController(
            defaults: temporaryDefaults(),
            blitzRecorderLicenseKeyStore: keyStore,
            blitzRecorderLicenseValidator: validator
        )

        await access.activateLicenseKey("bad-key")

        XCTAssertFalse(access.isPro)
        XCTAssertFalse(access.canUseIPhoneCamera)
        XCTAssertNil(keyStore.licenseKey)
        XCTAssertEqual(access.accessMessage, "License signature is invalid")
    }

    func testWrongPriceLicenseShowsReadableFailure() async {
        let keyStore = InMemoryLicenseKeyStore()
        let validator = StubLicenseValidator(
            result: .success(
                BlitzRecorderLicenseValidationResponse(
                    ok: false,
                    status: "wrong_product",
                    reason: "License is for a different Stripe price",
                    payload: nil
                )
            )
        )
        let access = AccessController(
            defaults: temporaryDefaults(),
            blitzRecorderLicenseKeyStore: keyStore,
            blitzRecorderLicenseValidator: validator
        )

        await access.activateLicenseKey("BRL1_wrong_price")

        XCTAssertFalse(access.hasActiveLicense)
        XCTAssertNil(keyStore.licenseKey)
        XCTAssertEqual(
            access.accessMessage,
            "This key is signed correctly, but it is for an old BlitzRecorder price. Paste the newer key you were given, or ask support to reissue it."
        )
    }

    func testPaidFeatureStoresUpgradeContext() {
        let access = AccessController(defaults: temporaryDefaults())

        XCTAssertFalse(access.requirePaidFeature("iPhone camera"))

        XCTAssertEqual(access.lockedFeatureName, "iPhone camera")
        XCTAssertEqual(access.upgradeTitle, "Unlock iPhone camera")
        XCTAssertEqual(
            access.accessMessage,
            "iPhone camera is locked. Get Early Price, then paste your key here to unlock it."
        )
    }

    func testActivationDeepLinkActivatesLicense() async {
        let keyStore = InMemoryLicenseKeyStore()
        let validator = StubLicenseValidator(
            result: .success(
                BlitzRecorderLicenseValidationResponse(
                    ok: true,
                    status: "active",
                    reason: nil,
                    payload: .init(licenseId: "br_test", email: "buyer@example.com", kind: "early_lifetime")
                )
            )
        )
        let access = AccessController(
            defaults: temporaryDefaults(),
            blitzRecorderLicenseKeyStore: keyStore,
            blitzRecorderLicenseValidator: validator
        )

        access.handleBlitzRecorderURL(URL(string: "blitzrecorder://activate?license_key=BRL1_deep_link")!)
        for _ in 0..<50 {
            if access.hasActiveLicense { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(access.hasActiveLicense)
        XCTAssertEqual(keyStore.licenseKey, "BRL1_deep_link")
        XCTAssertEqual(access.licenseEmail, "buyer@example.com")
    }

    private func temporaryDefaults() -> UserDefaults {
        let name = "dev.blitzreels.blitzrecorder.tests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name)!
    }
}

private final class InMemoryBlitzReelsTokenStore: BlitzReelsTokenStore {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? {
        token
    }

    func saveToken(_ token: String) -> Bool {
        self.token = token
        return true
    }

    func deleteToken() {
        token = nil
    }
}

private final class InMemoryLicenseKeyStore: BlitzRecorderLicenseKeyStore {
    var licenseKey: String?

    func loadLicenseKey() -> String? {
        licenseKey
    }

    func saveLicenseKey(_ licenseKey: String) -> Bool {
        self.licenseKey = licenseKey
        return true
    }

    func deleteLicenseKey() {
        licenseKey = nil
    }
}

private struct StubAppIntegrityChecker: AppIntegrityChecking {
    let status: AppIntegrityStatus

    func validateAppIntegrity() -> AppIntegrityStatus {
        status
    }
}

private final class StubBlitzReelsEntitlementChecker: BlitzReelsEntitlementChecking {
    private let result: Result<BlitzReelsEntitlementResponse, Error>
    private(set) var requestedTokens: [String] = []

    init(result: Result<BlitzReelsEntitlementResponse, Error>) {
        self.result = result
    }

    func entitlement(for token: String) async throws -> BlitzReelsEntitlementResponse {
        requestedTokens.append(token)
        return try result.get()
    }
}

private final class StubLicenseValidator: BlitzRecorderLicenseValidating {
    private let result: Result<BlitzRecorderLicenseValidationResponse, Error>
    private let delayNanoseconds: UInt64

    init(result: Result<BlitzRecorderLicenseValidationResponse, Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func validate(licenseKey: String) async throws -> BlitzRecorderLicenseValidationResponse {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}
