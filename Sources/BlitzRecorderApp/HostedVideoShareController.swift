import AppKit
import Observation

struct HostedLibraryVideo: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let sharePath: String?
    let duration: Double?
    let width: Int?
    let height: Int?
    let bytes: Int64
    let error: String?

    var isProcessing: Bool { ["queued", "processing"].contains(status) }
    var statusLabel: String {
        switch status {
        case "ready": "Ready to share"
        case "uploading": "Upload incomplete"
        case "queued": "Waiting to process"
        case "processing": "Preparing playback"
        case "failed": "Processing failed"
        case "revoked": "Removed"
        default: "Checking status"
        }
    }
}

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
    private(set) var videos: [HostedLibraryVideo] = []
    private(set) var isRefreshingVideos = false
    private(set) var libraryMessage: String?
    private(set) var libraryUpdatedAt: Date?
    @ObservationIgnored private var libraryEmail: String?
    @ObservationIgnored private var refreshAfterUpload = false
    private var projectShares: [ProjectShare] = []
    private struct ProjectShare: Codable {
        let projectPath: String
        let url: URL
    }
    private struct LibraryCache: Codable {
        let videos: [HostedLibraryVideo]
        let updatedAt: Date
    }
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
            await refreshVideos()
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
            clearLibrary()
            if challenge == nil { accountMessage = nil }
            return
        }
        do {
            account = try await client.send(.init(route: "account", token: token, body: nil))
            accountMessage = nil
            if isSubscribed { awaitingPayment = false }
            await refreshVideos()
        } catch {
            if (error as? HostingFailure)?.status == 401 {
                credentials.clear()
                account = nil
                awaitingPayment = false
                clearLibrary()
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
            clearLibrary()
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
                if let shareURL, let projectPath {
                    rememberShare(.init(projectPath: projectPath, url: shareURL))
                }
                if isRefreshingVideos { refreshAfterUpload = true }
                else { await refreshVideos() }
            } catch is CancellationError {
                transferMessage = "Upload paused. Resume continues from the saved parts."
            } catch {
                if (error as? HostingFailure)?.status == 401 {
                    credentials.clear()
                    account = nil
                    hasCheckedAccount = true
                    clearLibrary()
                }
                transferMessage = Task.isCancelled ? "Upload paused. Resume continues from the saved parts." : error.localizedDescription
            }
        }
    }

    func pause() { task?.cancel() }

    func watchURL(_ video: HostedLibraryVideo) -> URL? {
        guard video.status == "ready", let path = video.sharePath else { return nil }
        return try? client.shareURL(path)
    }

    func sharedURL(forProject path: String?) -> URL? {
        guard let path, isConnected else { return nil }
        return projectShares.first { $0.projectPath == path }.flatMap { receipt in
            videos.contains { watchURL($0) == receipt.url } ? receipt.url : nil
        }
    }

    private func libraryKey(_ suffix: String) -> String? {
        guard let email = libraryEmail else { return nil }
        return "HostingLibrary:\(client.origin.absoluteString):\(email):\(suffix)"
    }

    private func prepareLibrary() {
        guard let email = account?.email?.lowercased(), email != libraryEmail else { return }
        clearLibrary()
        libraryEmail = email
        if let key = libraryKey("videos"), let data = UserDefaults.standard.data(forKey: key),
           let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) {
            videos = cache.videos
            libraryUpdatedAt = cache.updatedAt
        }
        if let key = libraryKey("projects"), let data = UserDefaults.standard.data(forKey: key) {
            projectShares = (try? JSONDecoder().decode([ProjectShare].self, from: data)) ?? []
        }
    }

    private func rememberShare(_ receipt: ProjectShare) {
        prepareLibrary()
        shareURL = receipt.url
        projectShares.removeAll { $0.projectPath == receipt.projectPath }
        projectShares.insert(receipt, at: 0)
        if let key = libraryKey("projects"), let data = try? JSONEncoder().encode(projectShares) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func clearLibrary() {
        videos = []
        projectShares = []
        libraryEmail = nil
        libraryMessage = nil
        libraryUpdatedAt = nil
        shareURL = nil
    }

    func refreshVideos() async {
        guard !isRefreshingVideos, isConnected, let token = credentials.load() else { return }
        prepareLibrary()
        let email = libraryEmail
        isRefreshingVideos = true
        defer {
            isRefreshingVideos = false
            if refreshAfterUpload {
                refreshAfterUpload = false
                Task { await refreshVideos() }
            }
        }
        do {
            struct Library: Decodable { let assets: [HostedLibraryVideo] }
            let library: Library = try await client.send(.init(route: "assets", token: token, body: nil))
            guard credentials.load() == token, libraryEmail == email else { return }
            videos = library.assets.filter { $0.status != "revoked" }
            let updatedAt = Date()
            libraryUpdatedAt = updatedAt
            libraryMessage = nil
            if let key = libraryKey("videos"), let data = try? JSONEncoder().encode(
                LibraryCache(videos: videos, updatedAt: updatedAt)) {
                UserDefaults.standard.set(data, forKey: key)
            }
            if !isRunning { shareURL = sharedURL(forProject: projectPath) }
        } catch {
            guard credentials.load() == token, libraryEmail == email else { return }
            if (error as? HostingFailure)?.status == 401 {
                credentials.clear()
                account = nil
                clearLibrary()
                accountMessage = "Sign in again to see your shared videos."
            } else {
                libraryMessage = videos.isEmpty ? "Unable to load shared videos. Try again."
                    : "Couldn’t refresh. Showing your last synced videos."
            }
        }
    }
}
