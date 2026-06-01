import AppKit
import BlitzRecorderCore
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
    static let freeExportLimit = 3
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
    private let blitzReelsEntitlementChecker: BlitzReelsEntitlementChecking
    private let dateProvider: () -> Date
    private var transactionUpdatesTask: Task<Void, Never>?

    var monthlyProduct: Product?
    var annualProduct: Product?
    var usedFreeExports: Int
    var hasAppStoreSubscription = false
    var hasBlitzReelsEntitlement = false
    var blitzReelsPlanName: String?
    var isLoadingProducts = false
    var isPurchasing = false
    var accessMessage = ""

    init(
        defaults: UserDefaults? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        blitzReelsTokenStore: BlitzReelsTokenStore? = nil,
        blitzReelsEntitlementChecker: BlitzReelsEntitlementChecking = URLSessionBlitzReelsEntitlementChecker()
    ) {
        let resolvedDefaults = defaults ?? .standard
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
        self.blitzReelsEntitlementChecker = blitzReelsEntitlementChecker
        self.dateProvider = dateProvider
        usedFreeExports = max(0, resolvedDefaults.integer(forKey: Key.usedFreeExports))
        migrateLegacyBlitzReelsTokenIfNeeded()
        restoreCachedBlitzReelsEntitlement()
    }

    var isPro: Bool {
        hasAppStoreSubscription || hasBlitzReelsEntitlement
    }

    var freeExportsRemaining: Int {
        max(0, ProductConfiguration.freeExportLimit - usedFreeExports)
    }

    var canRenderExport: Bool {
        isPro || freeExportsRemaining > 0
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
        guard !isPro else { return }
        guard freeExportsRemaining > 0 else { return }
        usedFreeExports += 1
        defaults.set(usedFreeExports, forKey: Key.usedFreeExports)
    }

    func purchaseMonthly() async {
        await purchase(product: monthlyProduct, fallbackProductID: ProductConfiguration.monthlyProductID)
    }

    func purchaseAnnual() async {
        await purchase(product: annualProduct, fallbackProductID: ProductConfiguration.annualProductID)
    }

    private func purchase(product existingProduct: Product?, fallbackProductID: String) async {
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
        guard let token = blitzReelsTokenStore.loadToken(), !token.isEmpty else {
            clearBlitzReelsEntitlement()
            return
        }

        do {
            let entitlement = try await blitzReelsEntitlementChecker.entitlement(for: token)
            hasBlitzReelsEntitlement = entitlement.active
            blitzReelsPlanName = entitlement.active ? entitlement.planName : nil
            if let planName = blitzReelsPlanName {
                defaults.set(planName, forKey: Key.blitzReelsPlanName)
                defaults.set(dateProvider(), forKey: Key.blitzReelsVerifiedAt)
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
        guard blitzReelsTokenStore.loadToken()?.isEmpty == false,
              let planName = defaults.string(forKey: Key.blitzReelsPlanName),
              hasFreshBlitzReelsVerification else {
            clearBlitzReelsEntitlement()
            return
        }

        blitzReelsPlanName = planName
        hasBlitzReelsEntitlement = true
    }

    private var hasFreshBlitzReelsVerification: Bool {
        guard let verifiedAt = defaults.object(forKey: Key.blitzReelsVerifiedAt) as? Date else {
            return false
        }
        return dateProvider().timeIntervalSince(verifiedAt) <= ProductConfiguration.blitzReelsEntitlementCacheDuration
    }

    private func handleBlitzReelsVerificationUnavailable(_ error: Error? = nil) {
        if hasFreshBlitzReelsVerification, defaults.string(forKey: Key.blitzReelsPlanName) != nil {
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
