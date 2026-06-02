import AppKit
import BlitzRecorderCore
import CryptoKit
import Foundation
import Observation
import Security
import StoreKit

enum AppLinks {
    static let landingPage = BlitzRecorderProductIdentity.landingPage
    static let support = BlitzRecorderProductIdentity.supportURL
    static let privacy = BlitzRecorderProductIdentity.privacyURL
    static let terms = BlitzRecorderProductIdentity.termsURL
}

enum ProductConfiguration {
    static let monthlyProductID = "dev.blitzreels.blitzrecorder.pro.monthly"
    static let annualProductID = "dev.blitzreels.blitzrecorder.pro.annual"
    static let appStoreProductIDs = [monthlyProductID, annualProductID]
    static let blitzReelsSignInURL = URL(string: "https://www.blitzreels.com/blitzrecorder/sign-in")!
    static let blitzReelsEntitlementURL = URL(string: "https://www.blitzreels.com/api/blitzrecorder/entitlement")!
    static let freeExportLimit = 10
    static let blitzReelsEntitlementCacheDuration: TimeInterval = 7 * 24 * 60 * 60

    static func isAppStoreProductID(_ productID: String) -> Bool {
        appStoreProductIDs.contains(productID)
    }
}

struct BlitzReelsEntitlementResponse: Decodable {
    let active: Bool
    let planName: String?
}

struct BlitzReelsEntitlementHTTPError: Error {
    let statusCode: Int
}

protocol BlitzReelsEntitlementChecking {
    func entitlement(for token: String) async throws -> BlitzReelsEntitlementResponse
}

struct URLSessionBlitzReelsEntitlementChecker: BlitzReelsEntitlementChecking {
    func entitlement(for token: String) async throws -> BlitzReelsEntitlementResponse {
        var request = URLRequest(url: ProductConfiguration.blitzReelsEntitlementURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BlitzReelsEntitlementHTTPError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(BlitzReelsEntitlementResponse.self, from: data)
    }
}

protocol BlitzReelsTokenStore {
    func loadToken() -> String?
    @discardableResult
    func saveToken(_ token: String) -> Bool
    func deleteToken()
}

struct UserDefaultsBlitzReelsTokenStore: BlitzReelsTokenStore {
    let defaults: UserDefaults
    let key: String

    func loadToken() -> String? {
        defaults.string(forKey: key)
    }

    func saveToken(_ token: String) -> Bool {
        defaults.set(token, forKey: key)
        return defaults.string(forKey: key) == token
    }

    func deleteToken() {
        defaults.removeObject(forKey: key)
    }
}

struct KeychainBlitzReelsTokenStore: BlitzReelsTokenStore {
    private let service = "dev.blitzreels.blitzrecorder"
    private let account = "blitzreels-access-token"

    func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    func saveToken(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrIsInvisible as String] = true
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct RedundantBlitzReelsTokenStore: BlitzReelsTokenStore {
    let primary: BlitzReelsTokenStore
    let fallback: BlitzReelsTokenStore

    func loadToken() -> String? {
        if let token = primary.loadToken(), !token.isEmpty {
            return token
        }
        return fallback.loadToken()
    }

    func saveToken(_ token: String) -> Bool {
        let primarySaved = primary.saveToken(token)
        let fallbackSaved = fallback.saveToken(token)
        return primarySaved || fallbackSaved
    }

    func deleteToken() {
        primary.deleteToken()
        fallback.deleteToken()
    }
}

enum FreeExportCounterLoadResult {
    case missing
    case valid(Int)
    case invalid
}

protocol FreeExportCounterStoring {
    func load() -> FreeExportCounterLoadResult
    @discardableResult
    func save(_ count: Int) -> Bool
}

struct BlitzReelsCachedEntitlement {
    let planName: String
    let verifiedAt: Date
}

protocol BlitzReelsEntitlementCacheStoring {
    func load(for token: String, now: Date, maxAge: TimeInterval) -> BlitzReelsCachedEntitlement?
    @discardableResult
    func save(planName: String, token: String, verifiedAt: Date) -> Bool
    func clear()
}

enum AppIntegrityStatus {
    case trusted
    case failed(String)
}

protocol AppIntegrityChecking {
    func validateAppIntegrity() -> AppIntegrityStatus
}

struct RuntimeAppIntegrityChecker: AppIntegrityChecking {
    private let expectedBundleID = BlitzRecorderProductIdentity.macBundleID
    private let expectedTeamID = "54LJ85K2P7"

    func validateAppIntegrity() -> AppIntegrityStatus {
#if RELEASE_APP_INTEGRITY_CHECKS
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return .failed("Code signature could not be read.")
        }

        var requirement: SecRequirement?
        let requirementText = """
        identifier "\(expectedBundleID)" and anchor apple generic and certificate leaf[subject.OU] = "\(expectedTeamID)"
        """
        let requirementStatus = SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            return .failed("Code signature requirement could not be prepared.")
        }

        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
        let validationStatus = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        guard validationStatus == errSecSuccess else {
            return .failed("Code signature validation failed.")
        }
        return .trusted
#else
        return .trusted
#endif
    }
}

private protocol AccessDataStoring {
    func loadData() -> Data?
    @discardableResult
    func saveData(_ data: Data) -> Bool
    func deleteData()
}

private struct UserDefaultsAccessDataStore: AccessDataStoring {
    let defaults: UserDefaults
    let key: String

    func loadData() -> Data? {
        defaults.data(forKey: key)
    }

    func saveData(_ data: Data) -> Bool {
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    func deleteData() {
        defaults.removeObject(forKey: key)
    }
}

private struct KeychainAccessDataStore: AccessDataStoring {
    let service: String
    let account: String

    func loadData() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func saveData(_ data: Data) -> Bool {
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrIsInvisible as String] = true
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func deleteData() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private protocol AccessSigningKeyStoring {
    func loadKey(createIfMissing: Bool) -> Data?
}

private struct UserDefaultsAccessSigningKeyStore: AccessSigningKeyStoring {
    let defaults: UserDefaults
    let key: String

    func loadKey(createIfMissing: Bool) -> Data? {
        if let keyData = defaults.data(forKey: key), keyData.count >= 32 {
            return keyData
        }
        guard createIfMissing, let keyData = AccessRandom.bytes(count: 32) else {
            return nil
        }
        defaults.set(keyData, forKey: key)
        return defaults.data(forKey: key)
    }
}

private struct KeychainAccessSigningKeyStore: AccessSigningKeyStoring {
    let dataStore: KeychainAccessDataStore

    func loadKey(createIfMissing: Bool) -> Data? {
        if let keyData = dataStore.loadData(), keyData.count >= 32 {
            return keyData
        }
        guard createIfMissing, let keyData = AccessRandom.bytes(count: 32) else {
            return nil
        }
        guard dataStore.saveData(keyData) else {
            return nil
        }
        return dataStore.loadData()
    }
}

private enum AccessRandom {
    static func bytes(count: Int) -> Data? {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        return status == errSecSuccess ? data : nil
    }

    static func nonce() -> String {
        bytes(count: 16)?.base64EncodedString() ?? UUID().uuidString
    }
}

private struct AccessIntegritySigner {
    let keyStore: AccessSigningKeyStoring

    func sign(_ message: String) -> String? {
        guard let keyData = keyStore.loadKey(createIfMissing: true) else {
            return nil
        }
        let key = SymmetricKey(data: keyData)
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(code).base64EncodedString()
    }

    func verify(signature: String, message: String) -> Bool {
        guard let keyData = keyStore.loadKey(createIfMissing: false),
              let signatureData = Data(base64Encoded: signature) else {
            return false
        }
        let key = SymmetricKey(data: keyData)
        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: Data(message.utf8),
            using: key
        )
    }
}

private struct SignedFreeExportCounterStore: FreeExportCounterStoring {
    private struct Envelope: Codable {
        let version: Int
        let count: Int
        let issuedAtMilliseconds: Int64
        let nonce: String
        let signature: String
    }

    private let primary: AccessDataStoring
    private let mirror: AccessDataStoring?
    private let signer: AccessIntegritySigner

    init(defaults: UserDefaults, usesKeychain: Bool) {
        let service = "dev.blitzreels.blitzrecorder"
        if usesKeychain {
            primary = KeychainAccessDataStore(service: service, account: "free-export-counter")
            mirror = UserDefaultsAccessDataStore(defaults: defaults, key: "access.usedFreeExportsEnvelope")
            signer = AccessIntegritySigner(keyStore: KeychainAccessSigningKeyStore(
                dataStore: KeychainAccessDataStore(service: service, account: "local-integrity-key")
            ))
        } else {
            primary = UserDefaultsAccessDataStore(defaults: defaults, key: "access.usedFreeExportsEnvelope")
            mirror = nil
            signer = AccessIntegritySigner(keyStore: UserDefaultsAccessSigningKeyStore(
                defaults: defaults,
                key: "access.localIntegrityKey"
            ))
        }
    }

    func load() -> FreeExportCounterLoadResult {
        let primaryData = primary.loadData()
        let data = primaryData ?? mirror?.loadData()
        guard let data else {
            return .missing
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.count >= 0,
              signer.verify(signature: envelope.signature, message: signingMessage(for: envelope)) else {
            return .invalid
        }
        if primaryData == nil {
            _ = primary.saveData(data)
        }
        return .valid(envelope.count)
    }

    func save(_ count: Int) -> Bool {
        let envelope = unsignedEnvelope(count: max(0, count))
        guard let signature = signer.sign(signingMessage(for: envelope)) else {
            return false
        }
        let signedEnvelope = Envelope(
            version: envelope.version,
            count: envelope.count,
            issuedAtMilliseconds: envelope.issuedAtMilliseconds,
            nonce: envelope.nonce,
            signature: signature
        )
        guard let data = try? JSONEncoder().encode(signedEnvelope) else {
            return false
        }
        let primarySaved = primary.saveData(data)
        let mirrorSaved = mirror?.saveData(data) ?? true
        return primarySaved && mirrorSaved
    }

    private func unsignedEnvelope(count: Int) -> Envelope {
        Envelope(
            version: 1,
            count: count,
            issuedAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            nonce: AccessRandom.nonce(),
            signature: ""
        )
    }

    private func signingMessage(for envelope: Envelope) -> String {
        [
            "free-export-counter.v1",
            BlitzRecorderProductIdentity.macBundleID,
            String(ProductConfiguration.freeExportLimit),
            String(envelope.count),
            String(envelope.issuedAtMilliseconds),
            envelope.nonce
        ].joined(separator: "\n")
    }
}

private struct SignedBlitzReelsEntitlementCacheStore: BlitzReelsEntitlementCacheStoring {
    private struct Envelope: Codable {
        let version: Int
        let planName: String
        let verifiedAtMilliseconds: Int64
        let tokenDigest: String
        let nonce: String
        let signature: String
    }

    private let store: AccessDataStoring
    private let signer: AccessIntegritySigner

    init(defaults: UserDefaults, usesKeychain: Bool) {
        let service = "dev.blitzreels.blitzrecorder"
        store = UserDefaultsAccessDataStore(defaults: defaults, key: "access.blitzReelsEntitlementEnvelope")
        if usesKeychain {
            signer = AccessIntegritySigner(keyStore: KeychainAccessSigningKeyStore(
                dataStore: KeychainAccessDataStore(service: service, account: "local-integrity-key")
            ))
        } else {
            signer = AccessIntegritySigner(keyStore: UserDefaultsAccessSigningKeyStore(
                defaults: defaults,
                key: "access.localIntegrityKey"
            ))
        }
    }

    func load(for token: String, now: Date, maxAge: TimeInterval) -> BlitzReelsCachedEntitlement? {
        guard let data = store.loadData(),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              !envelope.planName.isEmpty,
              envelope.tokenDigest == Self.tokenDigest(token),
              signer.verify(signature: envelope.signature, message: signingMessage(for: envelope)) else {
            return nil
        }

        let verifiedAt = Date(timeIntervalSince1970: TimeInterval(envelope.verifiedAtMilliseconds) / 1_000)
        guard verifiedAt.timeIntervalSince(now) <= 5 * 60,
              now.timeIntervalSince(verifiedAt) <= maxAge else {
            return nil
        }
        return BlitzReelsCachedEntitlement(planName: envelope.planName, verifiedAt: verifiedAt)
    }

    func save(planName: String, token: String, verifiedAt: Date) -> Bool {
        let envelope = Envelope(
            version: 1,
            planName: planName,
            verifiedAtMilliseconds: Int64(verifiedAt.timeIntervalSince1970 * 1_000),
            tokenDigest: Self.tokenDigest(token),
            nonce: AccessRandom.nonce(),
            signature: ""
        )
        guard let signature = signer.sign(signingMessage(for: envelope)) else {
            return false
        }
        let signedEnvelope = Envelope(
            version: envelope.version,
            planName: envelope.planName,
            verifiedAtMilliseconds: envelope.verifiedAtMilliseconds,
            tokenDigest: envelope.tokenDigest,
            nonce: envelope.nonce,
            signature: signature
        )
        guard let data = try? JSONEncoder().encode(signedEnvelope) else {
            return false
        }
        return store.saveData(data)
    }

    func clear() {
        store.deleteData()
    }

    private static func tokenDigest(_ token: String) -> String {
        Data(SHA256.hash(data: Data(token.utf8))).base64EncodedString()
    }

    private func signingMessage(for envelope: Envelope) -> String {
        [
            "blitzreels-entitlement-cache.v1",
            BlitzRecorderProductIdentity.macBundleID,
            envelope.planName,
            String(envelope.verifiedAtMilliseconds),
            envelope.tokenDigest,
            envelope.nonce
        ].joined(separator: "\n")
    }
}

@Observable
@MainActor
final class AccessController {
    private enum Key {
        static let usedFreeExports = "access.usedFreeExports"
        static let blitzReelsAccessToken = "access.blitzReelsAccessToken"
        static let blitzReelsPlanName = "access.blitzReelsPlanName"
        static let blitzReelsVerifiedAt = "access.blitzReelsVerifiedAt"
    }

    private let defaults: UserDefaults
    private let blitzReelsTokenStore: BlitzReelsTokenStore
    private let freeExportCounterStore: FreeExportCounterStoring
    private let blitzReelsEntitlementCacheStore: BlitzReelsEntitlementCacheStoring
    private let blitzReelsEntitlementChecker: BlitzReelsEntitlementChecking
    private let dateProvider: () -> Date
    private var transactionUpdatesTask: Task<Void, Never>?

    var monthlyProduct: Product?
    var annualProduct: Product?
    var usedFreeExports: Int
    var hasAppStoreSubscription = false
    var hasBlitzReelsEntitlement = false
    var hasValidAppIntegrity = true
    var blitzReelsPlanName: String?
    var isLoadingProducts = false
    var isPurchasing = false
    var accessMessage = ""

    init(
        defaults: UserDefaults? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        blitzReelsTokenStore: BlitzReelsTokenStore? = nil,
        freeExportCounterStore: FreeExportCounterStoring? = nil,
        blitzReelsEntitlementCacheStore: BlitzReelsEntitlementCacheStoring? = nil,
        appIntegrityChecker: AppIntegrityChecking = RuntimeAppIntegrityChecker(),
        blitzReelsEntitlementChecker: BlitzReelsEntitlementChecking = URLSessionBlitzReelsEntitlementChecker()
    ) {
        let resolvedDefaults = defaults ?? .standard
        let usesKeychainStores = defaults == nil
        self.defaults = resolvedDefaults
        self.blitzReelsTokenStore = blitzReelsTokenStore
            ?? (defaults == nil
                ? RedundantBlitzReelsTokenStore(
                    primary: KeychainBlitzReelsTokenStore(),
                    fallback: UserDefaultsBlitzReelsTokenStore(
                        defaults: resolvedDefaults,
                        key: Key.blitzReelsAccessToken
                    )
                )
                : UserDefaultsBlitzReelsTokenStore(defaults: resolvedDefaults, key: Key.blitzReelsAccessToken))
        self.freeExportCounterStore = freeExportCounterStore
            ?? SignedFreeExportCounterStore(defaults: resolvedDefaults, usesKeychain: usesKeychainStores)
        self.blitzReelsEntitlementCacheStore = blitzReelsEntitlementCacheStore
            ?? SignedBlitzReelsEntitlementCacheStore(defaults: resolvedDefaults, usesKeychain: usesKeychainStores)
        self.blitzReelsEntitlementChecker = blitzReelsEntitlementChecker
        self.dateProvider = dateProvider
        switch appIntegrityChecker.validateAppIntegrity() {
        case .trusted:
            hasValidAppIntegrity = true
        case .failed(let reason):
            hasValidAppIntegrity = false
            accessMessage = "This copy of BlitzRecorder could not be verified. \(reason)"
        }
        switch self.freeExportCounterStore.load() {
        case .valid(let count):
            usedFreeExports = max(0, count)
        case .missing:
            usedFreeExports = max(0, resolvedDefaults.integer(forKey: Key.usedFreeExports))
            if usedFreeExports > 0 {
                _ = self.freeExportCounterStore.save(usedFreeExports)
            }
        case .invalid:
            usedFreeExports = ProductConfiguration.freeExportLimit
            accessMessage = "Free export allowance could not be verified."
        }
        migrateLegacyBlitzReelsTokenIfNeeded()
        restoreCachedBlitzReelsEntitlement()
    }

    var isPro: Bool {
        hasValidAppIntegrity && (hasAppStoreSubscription || hasBlitzReelsEntitlement)
    }

    var freeExportsRemaining: Int {
        max(0, ProductConfiguration.freeExportLimit - usedFreeExports)
    }

    var canRenderExport: Bool {
        hasValidAppIntegrity && (isPro || freeExportsRemaining > 0)
    }

    var hasBlitzReelsAccountConnection: Bool {
        blitzReelsTokenStore.loadToken()?.isEmpty == false
    }

    var monthlyPriceLabel: String {
        monthlyProduct?.displayPrice ?? "$7.99"
    }

    var annualPriceLabel: String {
        annualProduct?.displayPrice ?? "$49.99"
    }

    var accessLabel: String {
        if !hasValidAppIntegrity {
            return "App verification failed"
        }
        if hasAppStoreSubscription {
            return "Pro is on"
        }
        if hasBlitzReelsEntitlement {
            return blitzReelsPlanName.map { "Free with \($0)" } ?? "Free with BlitzReels"
        }
        return "\(freeExportsRemaining) free videos left"
    }

    func configure() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update)
            }
        }

        Task {
            await refreshProducts()
            await refreshEntitlements()
            await refreshBlitzReelsEntitlementIfNeeded()
        }
    }

    func recordSuccessfulExportIfNeeded() {
        guard hasValidAppIntegrity else { return }
        guard !isPro else { return }
        guard freeExportsRemaining > 0 else { return }
        let updatedCount = usedFreeExports + 1
        guard freeExportCounterStore.save(updatedCount) else {
            usedFreeExports = ProductConfiguration.freeExportLimit
            accessMessage = "Free export allowance could not be updated."
            return
        }
        usedFreeExports = updatedCount
    }

    func purchaseMonthly() async {
        await purchase(product: monthlyProduct, fallbackProductID: ProductConfiguration.monthlyProductID)
    }

    func purchaseAnnual() async {
        await purchase(product: annualProduct, fallbackProductID: ProductConfiguration.annualProductID)
    }

    private func purchase(product existingProduct: Product?, fallbackProductID: String) async {
        guard hasValidAppIntegrity else {
            accessMessage = "This copy of BlitzRecorder could not be verified."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let product: Product
            if let existingProduct {
                product = existingProduct
            } else {
                await refreshProducts()
                let loadedProduct = fallbackProductID == ProductConfiguration.monthlyProductID
                    ? monthlyProduct
                    : annualProduct
                guard let loadedProduct else {
                    accessMessage = "We couldn't load Pro. Try again soon."
                    return
                }
                product = loadedProduct
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                hasAppStoreSubscription = ProductConfiguration.isAppStoreProductID(transaction.productID)
                    && transaction.revocationDate == nil
                await transaction.finish()
                accessMessage = hasAppStoreSubscription ? "Pro is on." : ""
            case .userCancelled:
                accessMessage = "You cancelled the purchase."
            case .pending:
                accessMessage = "Your purchase is waiting for approval."
            @unknown default:
                accessMessage = "The purchase didn't go through."
            }
        } catch {
            accessMessage = "We couldn't finish the purchase: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        guard hasValidAppIntegrity else {
            accessMessage = "This copy of BlitzRecorder could not be verified."
            return
        }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            accessMessage = isPro ? "Your purchases are back." : "We didn't find a Pro plan to restore."
        } catch {
            accessMessage = "We couldn't restore your purchases: \(error.localizedDescription)"
        }
    }

    func openSubscriptionManagement() {
        let subscriptionsURL = URL(string: "macappstore://showSubscriptions")!
        if !NSWorkspace.shared.open(subscriptionsURL),
           let fallbackURL = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    func beginBlitzReelsSignIn() {
        var components = URLComponents(url: ProductConfiguration.blitzReelsSignInURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "return_to", value: "blitzrecorder://auth/blitzreels")
        ]
        NSWorkspace.shared.open(components?.url ?? ProductConfiguration.blitzReelsSignInURL)
    }

    func disconnectBlitzReels() {
        blitzReelsTokenStore.deleteToken()
        defaults.removeObject(forKey: Key.blitzReelsAccessToken)
        clearBlitzReelsEntitlement()
        accessMessage = "You're signed out of BlitzReels."
    }

    func handleBlitzReelsCallback(url: URL) {
        guard url.scheme == "blitzrecorder",
              url.host == "auth",
              url.path == "/blitzreels",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            accessMessage = "BlitzReels sign-in didn't work: \(error)"
            return
        }

        guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            accessMessage = "BlitzReels sign-in didn't work. Please try again."
            return
        }

        guard blitzReelsTokenStore.saveToken(token) else {
            accessMessage = "We couldn't save your BlitzReels sign-in. Please try again."
            return
        }
        Task { await refreshBlitzReelsEntitlement() }
    }

    func refreshBlitzReelsEntitlement() async {
        guard hasValidAppIntegrity else {
            clearBlitzReelsEntitlement()
            return
        }
        guard let token = blitzReelsTokenStore.loadToken(), !token.isEmpty else {
            clearBlitzReelsEntitlement()
            return
        }

        do {
            let entitlement = try await blitzReelsEntitlementChecker.entitlement(for: token)
            hasBlitzReelsEntitlement = entitlement.active
            blitzReelsPlanName = entitlement.active ? entitlement.planName : nil
            if let planName = blitzReelsPlanName {
                _ = blitzReelsEntitlementCacheStore.save(
                    planName: planName,
                    token: token,
                    verifiedAt: dateProvider()
                )
                defaults.removeObject(forKey: Key.blitzReelsPlanName)
                defaults.removeObject(forKey: Key.blitzReelsVerifiedAt)
                accessMessage = "Pro is free with \(planName)."
            } else {
                clearBlitzReelsEntitlement()
                accessMessage = "We didn't find a BlitzReels plan on your account."
            }
        } catch let error as BlitzReelsEntitlementHTTPError where error.statusCode == 401 || error.statusCode == 403 {
            blitzReelsTokenStore.deleteToken()
            defaults.removeObject(forKey: Key.blitzReelsAccessToken)
            clearBlitzReelsEntitlement()
            accessMessage = "Your BlitzReels sign-in expired. Please sign in again."
        } catch {
            handleBlitzReelsVerificationUnavailable(error)
        }
    }

    func refreshBlitzReelsEntitlementIfNeeded() async {
        guard hasBlitzReelsAccountConnection else {
            clearBlitzReelsEntitlement()
            return
        }
        guard !hasBlitzReelsEntitlement || !hasFreshBlitzReelsVerification else {
            return
        }
        await refreshBlitzReelsEntitlement()
    }

    private func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: ProductConfiguration.appStoreProductIDs)
            monthlyProduct = products.first { $0.id == ProductConfiguration.monthlyProductID }
            annualProduct = products.first { $0.id == ProductConfiguration.annualProductID }
        } catch {
            accessMessage = "We couldn't load Pro: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlements() async {
        guard hasValidAppIntegrity else {
            hasAppStoreSubscription = false
            return
        }
        var hasSubscription = false
        for await entitlement in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(entitlement)
                if ProductConfiguration.isAppStoreProductID(transaction.productID),
                   transaction.revocationDate == nil {
                    hasSubscription = true
                }
            } catch {
                continue
            }
        }
        hasAppStoreSubscription = hasSubscription
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(transactionResult)
            if ProductConfiguration.isAppStoreProductID(transaction.productID) {
                await refreshEntitlements()
            }
            await transaction.finish()
        } catch {
            accessMessage = "We couldn't check that purchase."
        }
    }

    private func restoreCachedBlitzReelsEntitlement() {
        guard let token = blitzReelsTokenStore.loadToken(), !token.isEmpty,
              let cachedEntitlement = cachedBlitzReelsEntitlement(for: token) else {
            clearBlitzReelsEntitlement()
            return
        }

        blitzReelsPlanName = cachedEntitlement.planName
        hasBlitzReelsEntitlement = true
    }

    private var hasFreshBlitzReelsVerification: Bool {
        guard let token = blitzReelsTokenStore.loadToken(), !token.isEmpty else {
            return false
        }
        return cachedBlitzReelsEntitlement(for: token) != nil
    }

    private func cachedBlitzReelsEntitlement(for token: String) -> BlitzReelsCachedEntitlement? {
        let now = dateProvider()
        if let signedEntitlement = blitzReelsEntitlementCacheStore.load(
            for: token,
            now: now,
            maxAge: ProductConfiguration.blitzReelsEntitlementCacheDuration
        ) {
            return signedEntitlement
        }
        return migrateLegacyBlitzReelsEntitlementCacheIfFresh(
            token: token,
            now: now,
            maxAge: ProductConfiguration.blitzReelsEntitlementCacheDuration
        )
    }

    private func migrateLegacyBlitzReelsEntitlementCacheIfFresh(
        token: String,
        now: Date,
        maxAge: TimeInterval
    ) -> BlitzReelsCachedEntitlement? {
        guard let planName = defaults.string(forKey: Key.blitzReelsPlanName),
              !planName.isEmpty,
              let verifiedAt = defaults.object(forKey: Key.blitzReelsVerifiedAt) as? Date,
              verifiedAt.timeIntervalSince(now) <= 5 * 60,
              now.timeIntervalSince(verifiedAt) <= maxAge,
              blitzReelsEntitlementCacheStore.save(planName: planName, token: token, verifiedAt: verifiedAt) else {
            return nil
        }
        defaults.removeObject(forKey: Key.blitzReelsPlanName)
        defaults.removeObject(forKey: Key.blitzReelsVerifiedAt)
        return BlitzReelsCachedEntitlement(planName: planName, verifiedAt: verifiedAt)
    }

    private func handleBlitzReelsVerificationUnavailable(_ error: Error? = nil) {
        if hasFreshBlitzReelsVerification {
            restoreCachedBlitzReelsEntitlement()
            accessMessage = "Using your saved BlitzReels access."
        } else {
            clearBlitzReelsEntitlement()
            if let error {
                accessMessage = "We couldn't check your BlitzReels access: \(error.localizedDescription)"
            } else {
                accessMessage = "We couldn't check your BlitzReels access right now."
            }
        }
    }

    private func migrateLegacyBlitzReelsTokenIfNeeded() {
        guard blitzReelsTokenStore.loadToken()?.isEmpty != false,
              let token = defaults.string(forKey: Key.blitzReelsAccessToken),
              !token.isEmpty else {
            return
        }

        if blitzReelsTokenStore.saveToken(token),
           blitzReelsTokenStore.loadToken()?.isEmpty == false {
            defaults.removeObject(forKey: Key.blitzReelsAccessToken)
        }
    }

    private func clearBlitzReelsEntitlement() {
        hasBlitzReelsEntitlement = false
        blitzReelsPlanName = nil
        blitzReelsEntitlementCacheStore.clear()
        defaults.removeObject(forKey: Key.blitzReelsPlanName)
        defaults.removeObject(forKey: Key.blitzReelsVerifiedAt)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw AccessError.failedVerification
        }
    }
}

enum AccessError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified."
    }
}
