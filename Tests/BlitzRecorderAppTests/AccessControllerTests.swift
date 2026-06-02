import Foundation
import XCTest
@testable import BlitzRecorderApp

@MainActor
final class AccessControllerTests: XCTestCase {
    func testAppStoreProductIDsIncludeMonthlyAndAnnualSubscriptions() {
        XCTAssertEqual(
            ProductConfiguration.appStoreProductIDs,
            [
                "dev.blitzreels.blitzrecorder.pro.monthly",
                "dev.blitzreels.blitzrecorder.pro.annual"
            ]
        )
        XCTAssertTrue(ProductConfiguration.isAppStoreProductID("dev.blitzreels.blitzrecorder.pro.monthly"))
        XCTAssertTrue(ProductConfiguration.isAppStoreProductID("dev.blitzreels.blitzrecorder.pro.annual"))
        XCTAssertFalse(ProductConfiguration.isAppStoreProductID("direct.license"))
    }

    func testFreeExportsAreAvailableUntilLimit() {
        let defaults = UserDefaults(suiteName: suiteName())!
        let access = AccessController(defaults: defaults)

        XCTAssertTrue(access.canRenderExport)
        XCTAssertEqual(access.freeExportsRemaining, ProductConfiguration.freeExportLimit)

        for _ in 0..<ProductConfiguration.freeExportLimit {
            access.recordSuccessfulExportIfNeeded()
        }

        XCTAssertFalse(access.canRenderExport)
        XCTAssertEqual(access.freeExportsRemaining, 0)

        access.recordSuccessfulExportIfNeeded()

        XCTAssertEqual(access.usedFreeExports, ProductConfiguration.freeExportLimit)
        XCTAssertNotNil(defaults.data(forKey: "access.usedFreeExportsEnvelope"))
    }

    func testCorruptNegativeLegacyFreeExportCountDoesNotExtendTrial() {
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set(-10, forKey: "access.usedFreeExports")

        let access = AccessController(defaults: defaults)

        XCTAssertEqual(access.usedFreeExports, 0)
        XCTAssertEqual(access.freeExportsRemaining, ProductConfiguration.freeExportLimit)
    }

    func testTamperingLegacyFreeExportCountDoesNotResetSignedCounter() {
        let defaults = UserDefaults(suiteName: suiteName())!
        let access = AccessController(defaults: defaults)

        for _ in 0..<ProductConfiguration.freeExportLimit {
            access.recordSuccessfulExportIfNeeded()
        }
        defaults.set(0, forKey: "access.usedFreeExports")

        let restoredAccess = AccessController(defaults: defaults)

        XCTAssertEqual(restoredAccess.usedFreeExports, ProductConfiguration.freeExportLimit)
        XCTAssertFalse(restoredAccess.canRenderExport)
    }

    func testCorruptSignedFreeExportCounterFailsClosed() {
        let defaults = UserDefaults(suiteName: suiteName())!
        let access = AccessController(defaults: defaults)
        access.recordSuccessfulExportIfNeeded()

        var envelope = defaults.data(forKey: "access.usedFreeExportsEnvelope")!
        envelope[envelope.startIndex] ^= 0xff
        defaults.set(envelope, forKey: "access.usedFreeExportsEnvelope")

        let restoredAccess = AccessController(defaults: defaults)

        XCTAssertEqual(restoredAccess.usedFreeExports, ProductConfiguration.freeExportLimit)
        XCTAssertFalse(restoredAccess.canRenderExport)
    }

    func testProAccessDoesNotConsumeFreeExports() {
        let defaults = UserDefaults(suiteName: suiteName())!
        let access = AccessController(defaults: defaults)
        access.hasAppStoreSubscription = true

        access.recordSuccessfulExportIfNeeded()

        XCTAssertTrue(access.canRenderExport)
        XCTAssertEqual(access.usedFreeExports, 0)
        XCTAssertEqual(access.freeExportsRemaining, ProductConfiguration.freeExportLimit)
    }

    func testFailedAppIntegrityBlocksFreeExportsAndProAccess() {
        let defaults = UserDefaults(suiteName: suiteName())!
        let access = AccessController(
            defaults: defaults,
            appIntegrityChecker: StubAppIntegrityChecker(status: .failed("Signature mismatch."))
        )

        XCTAssertFalse(access.hasValidAppIntegrity)
        XCTAssertFalse(access.canRenderExport)
        XCTAssertEqual(access.accessLabel, "App verification failed")
        XCTAssertEqual(access.accessMessage, "This copy of BlitzRecorder could not be verified. Signature mismatch.")

        access.recordSuccessfulExportIfNeeded()
        access.hasAppStoreSubscription = true

        XCTAssertFalse(access.isPro)
        XCTAssertEqual(access.usedFreeExports, 0)
        XCTAssertFalse(access.canRenderExport)
    }

    func testBlitzReelsCacheRequiresTokenAndFreshVerification() {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("BlitzReels Pro", forKey: "access.blitzReelsPlanName")
        defaults.set(now, forKey: "access.blitzReelsVerifiedAt")

        let missingToken = AccessController(defaults: defaults, dateProvider: { now })
        XCTAssertFalse(missingToken.hasBlitzReelsEntitlement)

        defaults.set("token", forKey: "access.blitzReelsAccessToken")
        defaults.set("BlitzReels Pro", forKey: "access.blitzReelsPlanName")
        defaults.set(now.addingTimeInterval(-ProductConfiguration.blitzReelsEntitlementCacheDuration - 1), forKey: "access.blitzReelsVerifiedAt")

        let expired = AccessController(defaults: defaults, dateProvider: { now })
        XCTAssertFalse(expired.hasBlitzReelsEntitlement)
    }

    func testFreshBlitzReelsCacheUnlocksProAndDisconnectClearsIt() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "token")
        let cacheWriter = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: StubBlitzReelsEntitlementChecker(result: .success(.init(active: true, planName: "BlitzReels Pro")))
        )
        await cacheWriter.refreshBlitzReelsEntitlement()

        let access = AccessController(defaults: defaults, dateProvider: { now }, blitzReelsTokenStore: tokenStore)

        XCTAssertTrue(access.hasBlitzReelsEntitlement)
        XCTAssertTrue(access.canRenderExport)
        XCTAssertEqual(access.accessLabel, "Free with BlitzReels Pro")

        access.disconnectBlitzReels()

        XCTAssertFalse(access.hasBlitzReelsEntitlement)
        XCTAssertNil(tokenStore.loadToken())
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsPlanName"))
        XCTAssertNil(defaults.object(forKey: "access.blitzReelsVerifiedAt"))
        XCTAssertNil(defaults.data(forKey: "access.blitzReelsEntitlementEnvelope"))
    }

    func testFreshLegacyBlitzReelsCacheMigratesToSignedCache() {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("BlitzReels Pro", forKey: "access.blitzReelsPlanName")
        defaults.set(now, forKey: "access.blitzReelsVerifiedAt")
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "legacy-cache-token")

        let access = AccessController(defaults: defaults, dateProvider: { now }, blitzReelsTokenStore: tokenStore)

        XCTAssertTrue(access.hasBlitzReelsEntitlement)
        XCTAssertTrue(access.isPro)
        XCTAssertEqual(access.accessLabel, "Free with BlitzReels Pro")
        XCTAssertNotNil(defaults.data(forKey: "access.blitzReelsEntitlementEnvelope"))
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsPlanName"))
        XCTAssertNil(defaults.object(forKey: "access.blitzReelsVerifiedAt"))
    }

    func testTamperedBlitzReelsCacheDoesNotUnlockPro() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "token")
        let cacheWriter = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: StubBlitzReelsEntitlementChecker(result: .success(.init(active: true, planName: "BlitzReels Pro")))
        )
        await cacheWriter.refreshBlitzReelsEntitlement()

        var envelope = defaults.data(forKey: "access.blitzReelsEntitlementEnvelope")!
        envelope[envelope.startIndex] ^= 0xff
        defaults.set(envelope, forKey: "access.blitzReelsEntitlementEnvelope")

        let access = AccessController(defaults: defaults, dateProvider: { now }, blitzReelsTokenStore: tokenStore)

        XCTAssertFalse(access.hasBlitzReelsEntitlement)
        XCTAssertFalse(access.isPro)
    }

    func testBlitzReelsConnectionCanExistWithoutActiveEntitlement() {
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("token", forKey: "access.blitzReelsAccessToken")

        let access = AccessController(defaults: defaults)

        XCTAssertTrue(access.hasBlitzReelsAccountConnection)
        XCTAssertFalse(access.hasBlitzReelsEntitlement)
        XCTAssertFalse(access.isPro)

        access.disconnectBlitzReels()

        XCTAssertFalse(access.hasBlitzReelsAccountConnection)
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsAccessToken"))
    }

    func testLegacyBlitzReelsTokenMigratesOutOfDefaults() {
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("legacy-token", forKey: "access.blitzReelsAccessToken")
        let tokenStore = InMemoryBlitzReelsTokenStore()

        let access = AccessController(defaults: defaults, blitzReelsTokenStore: tokenStore)

        XCTAssertTrue(access.hasBlitzReelsAccountConnection)
        XCTAssertEqual(tokenStore.loadToken(), "legacy-token")
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsAccessToken"))

        access.disconnectBlitzReels()

        XCTAssertFalse(access.hasBlitzReelsAccountConnection)
        XCTAssertNil(tokenStore.loadToken())
    }

    func testLegacyBlitzReelsTokenStaysInDefaultsWhenSecureMigrationFails() {
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("legacy-token", forKey: "access.blitzReelsAccessToken")
        let tokenStore = InMemoryBlitzReelsTokenStore()
        tokenStore.shouldSave = false

        let access = AccessController(defaults: defaults, blitzReelsTokenStore: tokenStore)

        XCTAssertFalse(access.hasBlitzReelsAccountConnection)
        XCTAssertNil(tokenStore.loadToken())
        XCTAssertEqual(defaults.string(forKey: "access.blitzReelsAccessToken"), "legacy-token")
    }

    func testRedundantTokenStoreMirrorsTokenAndFallsBackWhenPrimaryIsUnavailable() {
        let primary = InMemoryBlitzReelsTokenStore()
        primary.shouldSave = false
        let fallback = InMemoryBlitzReelsTokenStore()
        let store = RedundantBlitzReelsTokenStore(primary: primary, fallback: fallback)

        XCTAssertTrue(store.saveToken("token"))
        XCTAssertNil(primary.loadToken())
        XCTAssertEqual(fallback.loadToken(), "token")
        XCTAssertEqual(store.loadToken(), "token")

        store.deleteToken()

        XCTAssertNil(primary.loadToken())
        XCTAssertNil(fallback.loadToken())
        XCTAssertNil(store.loadToken())
    }

    func testActiveBlitzReelsEntitlementUnlocksProAndCachesVerification() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "eligible-token")
        let checker = StubBlitzReelsEntitlementChecker(result: .success(.init(active: true, planName: "BlitzReels Pro")))
        let access = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlement()

        XCTAssertTrue(access.hasBlitzReelsEntitlement)
        XCTAssertTrue(access.isPro)
        XCTAssertEqual(access.accessLabel, "Free with BlitzReels Pro")
        XCTAssertEqual(access.accessMessage, "Pro is free with BlitzReels Pro.")
        XCTAssertNotNil(defaults.data(forKey: "access.blitzReelsEntitlementEnvelope"))
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsPlanName"))
        XCTAssertNil(defaults.object(forKey: "access.blitzReelsVerifiedAt"))
        XCTAssertEqual(tokenStore.loadToken(), "eligible-token")
        XCTAssertEqual(checker.requestedTokens, ["eligible-token"])
    }

    func testInactiveBlitzReelsEntitlementKeepsConnectionButDoesNotUnlockPro() async {
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("Old Plan", forKey: "access.blitzReelsPlanName")
        defaults.set(Date(), forKey: "access.blitzReelsVerifiedAt")
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "ineligible-token")
        let checker = StubBlitzReelsEntitlementChecker(result: .success(.init(active: false, planName: nil)))
        let access = AccessController(
            defaults: defaults,
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlement()

        XCTAssertFalse(access.hasBlitzReelsEntitlement)
        XCTAssertFalse(access.isPro)
        XCTAssertEqual(access.accessMessage, "We didn't find a BlitzReels plan on your account.")
        XCTAssertEqual(tokenStore.loadToken(), "ineligible-token")
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsPlanName"))
        XCTAssertNil(defaults.object(forKey: "access.blitzReelsVerifiedAt"))
    }

    func testUnauthorizedBlitzReelsEntitlementDeletesTokenAndClearsAccess() async {
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("BlitzReels Pro", forKey: "access.blitzReelsPlanName")
        defaults.set(Date(), forKey: "access.blitzReelsVerifiedAt")
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "expired-token")
        let checker = StubBlitzReelsEntitlementChecker(result: .failure(BlitzReelsEntitlementHTTPError(statusCode: 401)))
        let access = AccessController(
            defaults: defaults,
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlement()

        XCTAssertFalse(access.hasBlitzReelsEntitlement)
        XCTAssertFalse(access.isPro)
        XCTAssertEqual(access.accessMessage, "Your BlitzReels sign-in expired. Please sign in again.")
        XCTAssertNil(tokenStore.loadToken())
        XCTAssertNil(defaults.string(forKey: "access.blitzReelsPlanName"))
        XCTAssertNil(defaults.object(forKey: "access.blitzReelsVerifiedAt"))
    }

    func testUnavailableBlitzReelsEntitlementUsesFreshCachedAccess() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "cached-token")
        let cacheWriter = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: StubBlitzReelsEntitlementChecker(result: .success(.init(active: true, planName: "BlitzReels Pro")))
        )
        await cacheWriter.refreshBlitzReelsEntitlement()

        let checker = StubBlitzReelsEntitlementChecker(result: .failure(URLError(.timedOut)))
        let access = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlement()

        XCTAssertTrue(access.hasBlitzReelsEntitlement)
        XCTAssertTrue(access.isPro)
        XCTAssertEqual(access.accessMessage, "Using your saved BlitzReels access.")
        XCTAssertEqual(access.accessLabel, "Free with BlitzReels Pro")
        XCTAssertEqual(tokenStore.loadToken(), "cached-token")
    }

    func testAutomaticBlitzReelsRefreshKeepsFreshCachedAccess() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "cached-token")
        let cacheWriter = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: StubBlitzReelsEntitlementChecker(result: .success(.init(active: true, planName: "BlitzReels Pro")))
        )
        await cacheWriter.refreshBlitzReelsEntitlement()

        let checker = StubBlitzReelsEntitlementChecker(result: .failure(BlitzReelsEntitlementHTTPError(statusCode: 401)))
        let access = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlementIfNeeded()

        XCTAssertTrue(access.hasBlitzReelsEntitlement)
        XCTAssertTrue(access.isPro)
        XCTAssertEqual(access.accessLabel, "Free with BlitzReels Pro")
        XCTAssertEqual(tokenStore.loadToken(), "cached-token")
        XCTAssertEqual(checker.requestedTokens, [])
    }

    func testAutomaticBlitzReelsRefreshChecksExpiredCache() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let defaults = UserDefaults(suiteName: suiteName())!
        defaults.set("Old Plan", forKey: "access.blitzReelsPlanName")
        defaults.set(now.addingTimeInterval(-ProductConfiguration.blitzReelsEntitlementCacheDuration - 1), forKey: "access.blitzReelsVerifiedAt")
        let tokenStore = InMemoryBlitzReelsTokenStore(token: "expired-cache-token")
        let checker = StubBlitzReelsEntitlementChecker(result: .success(.init(active: true, planName: "BlitzReels Pro")))
        let access = AccessController(
            defaults: defaults,
            dateProvider: { now },
            blitzReelsTokenStore: tokenStore,
            blitzReelsEntitlementChecker: checker
        )

        await access.refreshBlitzReelsEntitlementIfNeeded()

        XCTAssertTrue(access.hasBlitzReelsEntitlement)
        XCTAssertEqual(access.accessLabel, "Free with BlitzReels Pro")
        XCTAssertEqual(checker.requestedTokens, ["expired-cache-token"])
    }

    private func suiteName() -> String {
        let name = "dev.blitzreels.blitzrecorder.tests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return name
    }
}

private final class InMemoryBlitzReelsTokenStore: BlitzReelsTokenStore {
    private var token: String?
    var shouldSave = true

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() -> String? {
        token
    }

    func saveToken(_ token: String) -> Bool {
        guard shouldSave else { return false }
        self.token = token
        return true
    }

    func deleteToken() {
        token = nil
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
