import BlitzRecorderCore
import AppKit
import CryptoKit
import Foundation
import Observation
import Security

enum AppLinks {
    static let landingPage = BlitzRecorderProductIdentity.landingPage
    static let support = BlitzRecorderProductIdentity.supportURL
    static let privacy = BlitzRecorderProductIdentity.privacyURL
    static let terms = BlitzRecorderProductIdentity.termsURL
}

enum ProductConfiguration {
    static let blitzReelsSignInURL = URL(string: "https://blitzrecorder.com/sign-in")!
    static let blitzReelsEntitlementURL = URL(string: "https://blitzrecorder.com/api/blitzrecorder/entitlement")!
    static let licenseValidationURL = URL(string: "https://blitzrecorder.com/api/licenses/validate")!
    static let earlyPriceURL = URL(string: "https://blitzrecorder.com/upgrade?source=app_paywall")!

    /// Direct-to-checkout upgrade link with attribution. Sends a high-intent
    /// buyer straight to Stripe instead of the marketing homepage, and tags
    /// which locked feature drove the upgrade so the website can segment it.
    static func upgradeURL(feature: String?) -> URL {
        guard var components = URLComponents(string: "https://blitzrecorder.com/upgrade") else {
            return earlyPriceURL
        }
        var items = [URLQueryItem(name: "source", value: "app_paywall")]
        if let feature, !feature.isEmpty {
            items.append(URLQueryItem(name: "feature", value: feature))
        }
        components.queryItems = items
        return components.url ?? earlyPriceURL
    }
    static let freeExportLimit = 10
    static let blitzReelsEntitlementCacheDuration: TimeInterval = 7 * 24 * 60 * 60
}

struct BlitzReelsEntitlementResponse: Decodable {
    let active: Bool
    let planName: String?
}

struct BlitzReelsEntitlementHTTPError: Error {
    let statusCode: Int
}

struct BlitzRecorderLicenseValidationResponse: Decodable {
    struct Payload: Decodable {
        let licenseId: String
        let email: String
        let kind: String
    }

    let ok: Bool
    let status: String
    let reason: String?
    let payload: Payload?
}

struct BlitzRecorderLicenseValidationHTTPError: Error {
    let statusCode: Int
}

protocol BlitzReelsEntitlementChecking {
    func entitlement(for token: String) async throws -> BlitzReelsEntitlementResponse
}

protocol BlitzRecorderLicenseValidating {
    func validate(licenseKey: String) async throws -> BlitzRecorderLicenseValidationResponse
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

struct URLSessionBlitzRecorderLicenseValidator: BlitzRecorderLicenseValidating {
    private struct RequestBody: Encodable {
        let licenseKey: String
    }

    func validate(licenseKey: String) async throws -> BlitzRecorderLicenseValidationResponse {
        var request = URLRequest(url: ProductConfiguration.licenseValidationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(RequestBody(licenseKey: licenseKey))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if let validation = try? JSONDecoder().decode(BlitzRecorderLicenseValidationResponse.self, from: data) {
            return validation
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BlitzRecorderLicenseValidationHTTPError(statusCode: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(BlitzRecorderLicenseValidationResponse.self, from: data)
    }
}

protocol BlitzReelsTokenStore {
    func loadToken() -> String?
    @discardableResult
    func saveToken(_ token: String) -> Bool
    func deleteToken()
}

protocol BlitzRecorderLicenseKeyStore {
    func loadLicenseKey() -> String?
    @discardableResult
    func saveLicenseKey(_ licenseKey: String) -> Bool
    func deleteLicenseKey()
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

struct KeychainBlitzRecorderLicenseKeyStore: BlitzRecorderLicenseKeyStore {
    private let service = "dev.blitzreels.blitzrecorder"
    private let account = "blitzrecorder-license-key"

    func loadLicenseKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    func saveLicenseKey(_ licenseKey: String) -> Bool {
        let data = Data(licenseKey.utf8)
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

    func deleteLicenseKey() {
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

struct UserDefaultsBlitzRecorderLicenseKeyStore: BlitzRecorderLicenseKeyStore {
    let defaults: UserDefaults
    let key: String

    func loadLicenseKey() -> String? {
        defaults.string(forKey: key)
    }

    func saveLicenseKey(_ licenseKey: String) -> Bool {
        defaults.set(licenseKey, forKey: key)
        return defaults.string(forKey: key) == licenseKey
    }

    func deleteLicenseKey() {
        defaults.removeObject(forKey: key)
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
        static let blitzRecorderLicenseKey = "access.blitzRecorderLicenseKey"
    }

    private let defaults: UserDefaults
    private let blitzReelsTokenStore: BlitzReelsTokenStore
    private let freeExportCounterStore: FreeExportCounterStoring
    private let blitzReelsEntitlementCacheStore: BlitzReelsEntitlementCacheStoring
    private let blitzReelsEntitlementChecker: BlitzReelsEntitlementChecking
    private let blitzRecorderLicenseKeyStore: BlitzRecorderLicenseKeyStore
    private let blitzRecorderLicenseValidator: BlitzRecorderLicenseValidating
    private let dateProvider: () -> Date
    var onLicenseStateChanged: (() -> Void)?

    var usedFreeExports: Int
    var hasBlitzReelsEntitlement = false
    var hasActiveLicense = false
    var hasValidAppIntegrity = true
    var blitzReelsPlanName: String?
    var licenseEmail: String?
    var licenseID: String?
    var isLoadingProducts = false
    var isPurchasing = false
    var isValidatingLicense = false
    var accessMessage = ""
    var lockedFeatureName: String?

    init(
        defaults: UserDefaults? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        blitzReelsTokenStore: BlitzReelsTokenStore? = nil,
        freeExportCounterStore: FreeExportCounterStoring? = nil,
        blitzReelsEntitlementCacheStore: BlitzReelsEntitlementCacheStoring? = nil,
        blitzRecorderLicenseKeyStore: BlitzRecorderLicenseKeyStore? = nil,
        appIntegrityChecker: AppIntegrityChecking = RuntimeAppIntegrityChecker(),
        blitzReelsEntitlementChecker: BlitzReelsEntitlementChecking = URLSessionBlitzReelsEntitlementChecker(),
        blitzRecorderLicenseValidator: BlitzRecorderLicenseValidating = URLSessionBlitzRecorderLicenseValidator()
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
        self.blitzRecorderLicenseKeyStore = blitzRecorderLicenseKeyStore
            ?? (defaults == nil
                ? KeychainBlitzRecorderLicenseKeyStore()
                : UserDefaultsBlitzRecorderLicenseKeyStore(
                    defaults: resolvedDefaults,
                    key: Key.blitzRecorderLicenseKey
                ))
        self.blitzRecorderLicenseValidator = blitzRecorderLicenseValidator
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
            usedFreeExports = 0
        }
        migrateLegacyBlitzReelsTokenIfNeeded()
        restoreCachedBlitzReelsEntitlement()
    }

    var isPro: Bool {
        hasActiveLicense
    }

    var freeExportsRemaining: Int {
        ProductConfiguration.freeExportLimit
    }

    var canRenderExport: Bool {
        true
    }

    var canUseIPhoneCamera: Bool {
        hasActiveLicense
    }

    var canUse4KExport: Bool {
        hasActiveLicense
    }

    var canUse60FPSExport: Bool {
        hasActiveLicense
    }

    var hasBlitzReelsAccountConnection: Bool {
        blitzReelsTokenStore.loadToken()?.isEmpty == false
    }

    var hasSavedLicenseKey: Bool {
        blitzRecorderLicenseKeyStore.loadLicenseKey()?.isEmpty == false
    }

    var accessLabel: String {
        hasActiveLicense ? "Early Price license active" : "Free"
    }

    var upgradeTitle: String {
        if let lockedFeatureName {
            return "Unlock \(lockedFeatureName)"
        }
        return "Unlock the full studio"
    }

    var upgradeDetail: String {
        if let lockedFeatureName {
            return "\(lockedFeatureName) is included in Early Price with iPhone camera recording, 4K export, and 60 fps export."
        }
        return "Early Price unlocks iPhone camera recording, 4K export, and 60 fps export."
    }

    func configure() {
        isLoadingProducts = false
        isPurchasing = false
        hasBlitzReelsEntitlement = false
        blitzReelsPlanName = nil
        Task { await refreshLicenseIfNeeded() }
    }

    func recordSuccessfulExportIfNeeded() {
        usedFreeExports = 0
    }

    func beginBlitzReelsSignIn() {
        accessMessage = "No account is required."
    }

    func beginPurchase() {
        if let lockedFeatureName {
            accessMessage = "Opening checkout for \(lockedFeatureName). After payment, claim your key and paste it here."
        } else {
            accessMessage = "Opening checkout. After payment, claim your key and paste it here."
        }
        NSWorkspace.shared.open(ProductConfiguration.upgradeURL(feature: lockedFeatureName))
    }

    func activateLicenseKey(_ licenseKey: String) async {
        let normalizedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            accessMessage = "Paste your BlitzRecorder license key first."
            return
        }

        isValidatingLicense = true
        defer { isValidatingLicense = false }

        do {
            let validation = try await blitzRecorderLicenseValidator.validate(licenseKey: normalizedKey)
            guard validation.ok, validation.status == "active", let payload = validation.payload else {
                clearLicenseState(deleteStoredKey: true)
                accessMessage = validation.reason ?? "This license is not active."
                return
            }

            guard blitzRecorderLicenseKeyStore.saveLicenseKey(normalizedKey) else {
                accessMessage = "License is valid, but it could not be saved. Please try again."
                return
            }

            applyActiveLicense(payload)
            lockedFeatureName = nil
            accessMessage = "License activated for \(payload.email)."
        } catch {
            accessMessage = "We couldn't validate this license: \(error.localizedDescription)"
        }
    }

    func refreshLicenseIfNeeded() async {
        guard blitzRecorderLicenseKeyStore.loadLicenseKey()?.isEmpty == false else {
            clearLicenseState(deleteStoredKey: false)
            return
        }
        await refreshLicense()
    }

    func refreshLicense() async {
        guard let licenseKey = blitzRecorderLicenseKeyStore.loadLicenseKey(), !licenseKey.isEmpty else {
            clearLicenseState(deleteStoredKey: false)
            accessMessage = "No BlitzRecorder license is saved."
            return
        }

        isValidatingLicense = true
        defer { isValidatingLicense = false }

        do {
            let validation = try await blitzRecorderLicenseValidator.validate(licenseKey: licenseKey)
            guard validation.ok, validation.status == "active", let payload = validation.payload else {
                clearLicenseState(deleteStoredKey: true)
                accessMessage = validation.reason ?? "Your saved license is no longer active."
                return
            }

            applyActiveLicense(payload)
            accessMessage = "License active for \(payload.email)."
        } catch {
            hasActiveLicense = false
            accessMessage = "We couldn't check your license: \(error.localizedDescription)"
        }
    }

    func clearLicense() {
        clearLicenseState(deleteStoredKey: true)
        accessMessage = "License removed from this Mac."
    }

    @discardableResult
    func requirePaidFeature(_ featureName: String) -> Bool {
        guard hasActiveLicense else {
            lockedFeatureName = featureName
            accessMessage = "\(featureName) is locked. Get Early Price, then paste your key here to unlock it."
            return false
        }
        return true
    }

    func disconnectBlitzReels() {
        blitzReelsTokenStore.deleteToken()
        defaults.removeObject(forKey: Key.blitzReelsAccessToken)
        clearBlitzReelsEntitlement()
        accessMessage = "You're signed out of BlitzReels."
    }

    func handleBlitzReelsCallback(url: URL) {
        guard isBlitzReelsAuthCallback(url: url) else {
            return
        }

        handleBlitzReelsAuthCallback(url: url)
    }

    func handleBlitzRecorderURL(_ url: URL) {
        guard url.scheme == "blitzrecorder" else {
            return
        }

        if isLicenseActivationURL(url: url) {
            handleLicenseActivationURL(url)
            return
        }

        if isBlitzReelsAuthCallback(url: url) {
            handleBlitzReelsAuthCallback(url: url)
        }
    }

    private func isLicenseActivationURL(url: URL) -> Bool {
        url.host == "activate" || url.path == "/activate"
    }

    private func handleLicenseActivationURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let licenseKey = components.queryItems?.first(where: {
                  $0.name == "license_key" || $0.name == "key"
              })?.value,
              !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            accessMessage = "Open the license claim page again, or paste your license key here."
            return
        }

        accessMessage = "Activating license..."
        Task { await activateLicenseKey(licenseKey) }
    }

    private func isBlitzReelsAuthCallback(url: URL) -> Bool {
        guard url.scheme == "blitzrecorder",
              url.host == "auth",
              url.path == "/blitzreels" else {
            return false
        }
        return true
    }

    private func handleBlitzReelsAuthCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
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
        clearBlitzReelsEntitlement()
        accessMessage = "BlitzRecorder has a free 1080p tier. Early Price unlocks iPhone camera, 4K, and 60 fps."
    }

    func refreshBlitzReelsEntitlementIfNeeded() async {
        clearBlitzReelsEntitlement()
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

    private func applyActiveLicense(_ payload: BlitzRecorderLicenseValidationResponse.Payload) {
        hasActiveLicense = true
        licenseEmail = payload.email
        licenseID = payload.licenseId
        onLicenseStateChanged?()
    }

    private func clearLicenseState(deleteStoredKey: Bool) {
        hasActiveLicense = false
        licenseEmail = nil
        licenseID = nil
        if deleteStoredKey {
            blitzRecorderLicenseKeyStore.deleteLicenseKey()
            defaults.removeObject(forKey: Key.blitzRecorderLicenseKey)
        }
        onLicenseStateChanged?()
    }

}
