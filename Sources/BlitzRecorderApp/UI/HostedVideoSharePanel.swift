import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class HostedVideoShareController {
    static let shared = HostedVideoShareController(client: .configured)
    private(set) var fileURL: URL?
    @ObservationIgnored private var selectedFingerprint: String?
    private(set) var shareURL: URL?
    private(set) var progress = 0.0
    private(set) var message: String?
    private(set) var isRunning = false
    private(set) var isProcessing = false
    private(set) var isConnected: Bool
    private(set) var isSubscribed = false
    private(set) var plan: HostingPlan?
    @ObservationIgnored private let identity = BlitzReelsConnection(client: .configured)
    @ObservationIgnored private let client: HostingClient
    @ObservationIgnored private let credentials: HostingCredentialStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(client: HostingClient) {
        self.client = client
        credentials = .init(origin: client.origin)
        isConnected = credentials.load() != nil
        if let data = UserDefaults.standard.data(forKey: "HostingExport:\(client.origin.absoluteString)") {
            var stale = false
            fileURL = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil, bookmarkDataIsStale: &stale)
        }
    }

    func select(_ url: URL) {
        guard !isRunning else {
            if fileURL != url { message = "Finish or pause the current upload before sharing another video." }
            return
        }
        let fingerprint = try? HostingExportMetadata.fingerprint(url)
        guard fileURL != url || selectedFingerprint != fingerprint else { return }
        fileURL = url
        selectedFingerprint = fingerprint
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "HostingExport:\(client.origin.absoluteString)")
        }
        shareURL = nil
        progress = 0
        isProcessing = false
        message = nil
    }

    private struct Account: Decodable { let active: Bool }
    private struct Connection: Decodable { let token: String; let active: Bool }
    private struct Billing: Decodable { let url: URL }

    func connect() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let authorization = try await identity.hostingAuthorization()
            let result: Connection = try await client.send(.init(route: "connect", token: authorization, body: Data("{}".utf8)))
            try credentials.save(result.token)
            isConnected = true
            isSubscribed = result.active
            message = nil
        } catch is CancellationError {
        } catch { message = error.localizedDescription }
    }

    func refresh() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            plan = try await client.send(.init(route: "plan", token: nil, body: nil))
            message = nil
        } catch {
            plan = nil
            message = (error as? HostingFailure)?.status == 404
                ? "Video hosting is not available on this server yet. You can save your video to this Mac."
                : "The hosting service could not be reached. Check your connection and try again."
            return
        }
        guard plan?.available == true, let token = credentials.load() else { return }
        do {
            let account: Account = try await client.send(.init(route: "account", token: token, body: nil))
            isSubscribed = account.active
            message = nil
        } catch {
            if (error as? HostingFailure)?.status == 401 {
                credentials.clear()
                isConnected = false
                isSubscribed = false
            }
            message = error.localizedDescription
        }
    }

    func openBilling() async {
        guard !isRunning, let token = credentials.load() else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let billing: Billing = try await client.send(.init(route: "billing", token: token, body: Data("{}".utf8)))
            guard billing.url.scheme == "https", ["checkout.stripe.com", "billing.stripe.com"].contains(billing.url.host ?? "") else {
                throw HostingFailure(message: "The subscription page could not be opened.")
            }
            NSWorkspace.shared.open(billing.url)
        } catch { message = error.localizedDescription }
    }

    func disconnect() async {
        guard !isRunning, let token = credentials.load() else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            struct Result: Decodable { let disconnected: Bool }
            let _: Result = try await client.send(.init(route: "disconnect", token: token, body: Data("{}".utf8)))
            credentials.clear()
            isConnected = false
            isSubscribed = false
            shareURL = nil
            message = nil
        } catch { message = error.localizedDescription }
    }

    func start() {
        guard !isRunning, isSubscribed, let fileURL, let token = credentials.load() else { return }
        isRunning = true
        message = nil
        let metadata = HostingExportMetadata.load(fileURL) ?? .init(
            title: fileURL.deletingPathExtension().lastPathComponent, details: .empty)
        task = Task {
            var access = SecurityScopedResourceAccess(urls: [fileURL])
            access.start()
            defer { access.stop() }
            do {
                let url = try await client.upload(.init(fileURL: fileURL, token: token, metadata: metadata,
                    progress: { update in
                        await MainActor.run {
                            switch update {
                            case .uploading(let value): self.progress = value; self.isProcessing = false
                            case .processing: self.isProcessing = true
                            }
                        }
                    }))
                try Task.checkCancellation()
                shareURL = url
            } catch is CancellationError {
                message = "Paused. Resume continues from the parts already uploaded."
            } catch {
                message = Task.isCancelled ? "Paused. Resume continues from the parts already uploaded." : error.localizedDescription
            }
            isRunning = false
            task = nil
        }
    }

    func pause() { task?.cancel() }
}

struct HostedVideoSharePanel: View {
    struct ExportPreparation {
        let title: String
        let export: () -> Void
    }

    @Bindable var controller: HostedVideoShareController
    let preparation: ExportPreparation?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Share video").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .blitzButton(.quiet)
                    .accessibilityLabel("Close sharing")
                    .help("Close sharing. Your upload continues in the background.")
            }
            if let preparation {
                Label(preparation.title, systemImage: "film")
                    .font(.system(size: 13, weight: .medium)).lineLimit(2)
            } else if let file = controller.fileURL {
                Label(file.lastPathComponent, systemImage: "film")
                    .font(.system(size: 13, weight: .medium)).lineLimit(2)
            }
            if let plan = controller.plan, !controller.isSubscribed {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(plan.price) / month, excluding tax").font(.system(size: 16, weight: .semibold))
                    Text(plan.allowance)
                    Text("Streaming up to \(plan.maximumResolution)p · Transcript and chapters included when available")
                    Text("Links work while subscribed. Hosted files are removed \(plan.retentionDaysAfterExpiry) days after expiry.")
                }
                .font(.system(size: 12))
                .foregroundStyle(BlitzUI.supportingText)
            }
            if controller.plan == nil {
                if controller.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking video hosting…").font(.system(size: 13))
                    }
                } else {
                    Button("Try again") { Task { await controller.refresh() } }.blitzButton(.secondary)
                }
            } else if controller.plan?.available == false {
                Text("Video hosting is being prepared. You can save your video to this Mac in the meantime.")
                    .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
            } else if !controller.isConnected {
                Text("Connect your BlitzReels account to host videos on BlitzRecorder.")
                    .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                Button(controller.isRunning ? "Connecting…" : "Continue with BlitzReels") {
                    Task { await controller.connect() }
                }
                .blitzButton(.accent)
                .disabled(controller.isRunning)
            } else if !controller.isSubscribed {
                Text("Video hosting is a separate subscription. Review the price and storage plan before subscribing.")
                    .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                HStack {
                    Button("View hosting plan") { Task { await controller.openBilling() } }.blitzButton(.accent)
                    Button("Check subscription") { Task { await controller.refresh() } }.blitzButton(.secondary)
                }.disabled(controller.isRunning)
            } else if let preparation {
                Text("Export your current edit, upload it, then copy the link. A local copy is also saved.")
                    .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                Button("Export & upload", action: preparation.export)
                    .blitzButton(.accent)
                    .disabled(controller.isRunning)
                if controller.isRunning {
                    Text("Finish or pause the current upload before sharing another video.")
                        .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    Button("Pause current upload") { controller.pause() }.blitzButton(.secondary)
                }
            } else if let url = controller.shareURL {
                Text("Your video is ready to watch.")
                    .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                Text(url.absoluteString).font(.system(size: 12)).textSelection(.enabled)
                HStack {
                    Button(copied ? "Link copied" : "Copy link") {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }.blitzButton(.accent)
                    Button("Open video") { NSWorkspace.shared.open(url) }.blitzButton(.secondary)
                }
            } else {
                Text("Anyone with the link can watch. The transcript and chapters are included when available.")
                    .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                if controller.isRunning {
                    HStack {
                        Text(controller.isProcessing ? "Preparing streaming video…" : "Uploading video…")
                        Spacer()
                        if !controller.isProcessing { Text(controller.progress, format: .percent.precision(.fractionLength(0))) }
                    }.font(.system(size: 12)).monospacedDigit()
                    ProgressView(value: controller.isProcessing ? nil : controller.progress).tint(BlitzUI.mint)
                    Button(controller.isProcessing ? "Check later" : "Pause upload") { controller.pause() }
                        .blitzButton(.secondary)
                } else {
                    Button(controller.message == nil ? "Upload video" : "Resume sharing") { controller.start() }
                        .blitzButton(.accent)
                }
            }
            if controller.isConnected {
                HStack {
                    Button("Manage subscription") { Task { await controller.openBilling() } }.blitzButton(.quiet)
                    Spacer()
                    Button("Disconnect") { Task { await controller.disconnect() } }.blitzButton(.quiet)
                }.controlSize(.small).disabled(controller.isRunning)
            }
            if let message = controller.message {
                Text(message).font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .controlSize(.regular)
        .task { await controller.refresh() }
    }
}
