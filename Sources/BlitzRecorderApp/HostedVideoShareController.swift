import AppKit
import Observation

@MainActor
@Observable
final class HostedVideoShareController {
    enum AccountOperation { case checking, sendingCode, verifyingCode, openingBilling, signingOut }
    struct Account: Decodable, Equatable {
        let active: Bool
        let email: String?
    }
    struct SignInChallenge: Decodable {
        let challenge: String
        let email: String
        let expiresIn: Int
        let retryAfter: Int
    }
    struct Selection {
        let fileURL: URL
        let projectPath: String?
    }
    private struct Connection: Decodable { let token: String; let active: Bool; let email: String? }
    private struct Billing: Decodable { let url: URL }

    static let shared = HostedVideoShareController(client: .configured)
    private(set) var fileURL: URL?
    private(set) var projectPath: String?
    private(set) var shareURL: URL?
    private(set) var transferProgress: HostingClient.Progress?
    private(set) var transferMessage: String?
    private(set) var isRunning = false
    private(set) var account: Account?
    private(set) var accountOperation: AccountOperation?
    private(set) var accountMessage: String?
    private(set) var hasCheckedAccount = false
    private(set) var plan: HostingPlan?
    private(set) var challenge: SignInChallenge?
    private(set) var resendAfter = Date.distantPast
    private(set) var awaitingPayment = false
    @ObservationIgnored private var selectedFingerprint: String?
    @ObservationIgnored private let client: HostingClient
    @ObservationIgnored private let credentials: HostingCredentialStore
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var billingTask: Task<Void, Never>?

    var isConnected: Bool { account != nil }
    var isSubscribed: Bool { account?.active == true }
    var message: String? { transferMessage ?? accountMessage }

    init(client: HostingClient) {
        self.client = client
        credentials = .init(origin: client.origin)
        if let data = UserDefaults.standard.data(forKey: "HostingExport:\(client.origin.absoluteString)") {
            var stale = false
            fileURL = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
            projectPath = UserDefaults.standard.string(forKey: "HostingProject:\(client.origin.absoluteString)")
        }
    }

    func belongsToProject(_ path: String?) -> Bool {
        guard let path, path == projectPath, let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func select(_ selection: Selection) {
        guard !isRunning else { return }
        let url = selection.fileURL
        let fingerprint = try? HostingExportMetadata.fingerprint(url)
        guard fileURL != url || selectedFingerprint != fingerprint || projectPath != selection.projectPath else { return }
        fileURL = url
        projectPath = selection.projectPath
        UserDefaults.standard.set(projectPath, forKey: "HostingProject:\(client.origin.absoluteString)")
        selectedFingerprint = fingerprint
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "HostingExport:\(client.origin.absoluteString)")
        }
        shareURL = nil
        transferProgress = nil
        transferMessage = nil
    }

    func requestCode(email: String) async {
        guard accountOperation == nil, Date() >= resendAfter else { return }
        accountOperation = .sendingCode
        accountMessage = nil
        defer { accountOperation = nil }
        do {
            challenge = try await client.send(.init(route: "sign-in/request", token: nil,
                body: JSONSerialization.data(withJSONObject: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines)])))
            resendAfter = Date().addingTimeInterval(TimeInterval(challenge?.retryAfter ?? 60))
        } catch { accountMessage = error.localizedDescription }
    }

    func verifyCode(_ code: String) async {
        guard accountOperation == nil, let challenge else { return }
        accountOperation = .verifyingCode
        accountMessage = nil
        defer { accountOperation = nil }
        do {
            let result: Connection = try await client.send(.init(route: "sign-in/verify", token: nil,
                body: JSONSerialization.data(withJSONObject: ["challenge": challenge.challenge, "code": code])))
            try credentials.save(result.token)
            account = .init(active: result.active, email: result.email)
            self.challenge = nil
            hasCheckedAccount = true
        } catch { accountMessage = error.localizedDescription }
    }

    func changeEmail() {
        guard accountOperation == nil else { return }
        challenge = nil
        resendAfter = .distantPast
        accountMessage = nil
    }

    func refresh() async {
        guard accountOperation == nil else { return }
        accountOperation = .checking
        defer { accountOperation = nil; hasCheckedAccount = true }
        do {
            plan = try await client.send(.init(route: "plan", token: nil, body: nil))
        } catch {
            accountMessage = (error as? HostingFailure)?.status == 404
                ? "Video hosting is not available on this server yet. You can save your video to this Mac."
                : "Unable to refresh your account. Check your connection and try again."
            return
        }
        guard plan?.available == true else { return }
        guard let token = credentials.load() else {
            account = nil
            if challenge == nil { accountMessage = nil }
            return
        }
        do {
            account = try await client.send(.init(route: "account", token: token, body: nil))
            accountMessage = nil
            if isSubscribed { awaitingPayment = false }
        } catch {
            if (error as? HostingFailure)?.status == 401 {
                credentials.clear()
                account = nil
                awaitingPayment = false
            }
            accountMessage = error.localizedDescription
        }
    }

    func openBilling() async {
        guard accountOperation == nil, let token = credentials.load() else { return }
        accountOperation = .openingBilling
        accountMessage = nil
        defer { accountOperation = nil }
        do {
            let billing: Billing = try await client.send(.init(route: "billing", token: token, body: Data("{}".utf8)))
            guard billing.url.scheme == "https", ["checkout.stripe.com", "billing.stripe.com"].contains(billing.url.host ?? "") else {
                throw HostingFailure(message: "The subscription page could not be opened.")
            }
            guard NSWorkspace.shared.open(billing.url) else {
                throw HostingFailure(message: "The subscription page could not be opened. Try again.")
            }
            awaitingPayment = !isSubscribed
            billingTask?.cancel()
            billingTask = Task { [weak self] in
                for _ in 0..<100 {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    guard let self else { return }
                    await self.refresh()
                    if !self.awaitingPayment { return }
                }
                self?.awaitingPayment = false
            }
        } catch { accountMessage = error.localizedDescription }
    }

    func disconnect() async {
        guard accountOperation == nil, !isRunning, let token = credentials.load() else { return }
        accountOperation = .signingOut
        defer { accountOperation = nil }
        do {
            struct Result: Decodable { let disconnected: Bool }
            let _: Result = try await client.send(.init(route: "disconnect", token: token, body: Data("{}".utf8)))
            billingTask?.cancel()
            credentials.clear()
            account = nil
            challenge = nil
            awaitingPayment = false
            shareURL = nil
            accountMessage = nil
            transferMessage = nil
        } catch { accountMessage = error.localizedDescription }
    }

    func start() {
        guard !isRunning, accountOperation != .signingOut, isSubscribed, let fileURL, let token = credentials.load() else { return }
        isRunning = true
        transferMessage = nil
        shareURL = nil
        transferProgress = .preparing
        let metadata = HostingExportMetadata.load(fileURL) ?? .init(
            title: fileURL.deletingPathExtension().lastPathComponent, details: .empty)
        task = Task {
            var access = SecurityScopedResourceAccess(urls: [fileURL])
            access.start()
            defer { access.stop(); isRunning = false; task = nil }
            do {
                shareURL = try await client.upload(.init(fileURL: fileURL, token: token, metadata: metadata,
                    progress: { update in await MainActor.run { self.transferProgress = update } }))
            } catch is CancellationError {
                transferMessage = "Upload paused. Resume continues from the saved parts."
            } catch {
                if (error as? HostingFailure)?.status == 401 {
                    credentials.clear()
                    account = nil
                    hasCheckedAccount = true
                }
                transferMessage = Task.isCancelled ? "Upload paused. Resume continues from the saved parts." : error.localizedDescription
            }
        }
    }

    func pause() { task?.cancel() }
}
