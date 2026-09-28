import AppKit
import SwiftUI

struct HostedVideoSharePanel: View {
    enum Context {
        case project(String?)
        case account
    }
    struct ExportPreparation {
        let title: String
        let summary: String
        let status: EditorExportStatus?
        let export: () -> Void
    }

    @Bindable var controller: HostedVideoShareController
    let context: Context
    let preparation: ExportPreparation?
    let newExport: () -> Void
    let close: () -> Void
    let showLibrary: () -> Void
    @State private var email = ""
    @State private var code = ""
    @State private var copied = false
    @FocusState private var focusedField: Field?
    private enum Field { case email, code }

    private var isAccountOnly: Bool {
        if case .account = context { return true }
        return false
    }

    private var previousShare: URL? {
        guard case .project(let path) = context else { return nil }
        return controller.sharedURL(forProject: path)
    }

    private var currentShare: URL? {
        guard case .project(let path) = context, let path else { return nil }
        return controller.projectPath == path ? controller.shareURL ?? previousShare : previousShare
    }

    private var isSaving: Bool {
        if case .exporting = preparation?.status { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !isAccountOnly {
                Button(action: close) { Image(systemName: "arrow.left") }
                    .blitzButton(.quiet).controlSize(.small)
                    .accessibilityLabel("Back to editing")
                    .help("Back to editing. Sharing continues in the background.")
                }
                Text(isAccountOnly ? "Your BlitzRecorder account" : "Share video").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !isAccountOnly {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(controller.isRunning ? controller.fileURL?.lastPathComponent ?? "Video"
                             : preparation?.title ?? controller.fileURL?.lastPathComponent ?? "Your video")
                            .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        Text("A watch page on BlitzRecorder, ready to share.")
                            .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    }
                    if let url = previousShare, preparation != nil || controller.isRunning || isSaving {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Previously shared", systemImage: "link")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(BlitzUI.mint)
                            HostedVideoLinkActions(url: url)
                            Text("This link keeps the version you shared. Share the current edit to create a new version.")
                                .font(.system(size: 11)).foregroundStyle(BlitzUI.supportingText)
                        }
                        Divider()
                    }
                    }
                    if !isAccountOnly, controller.isRunning, let progress = controller.transferProgress {
                        HostedVideoProgressView(presentation: .transfer(progress))
                        if progress != .processing {
                            Button("Pause upload", action: controller.pause).blitzButton(.secondary)
                        }
                        Text("You can keep editing while your video is prepared.")
                            .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    } else if !isAccountOnly, isSaving, let preparation, case .exporting(let progress) = preparation.status {
                        HostedVideoProgressView(presentation: .exporting(progress))
                    } else if !controller.hasCheckedAccount {
                        activity("Loading your BlitzRecorder account")
                    } else if controller.plan == nil || controller.plan?.available == false {
                        Text("Sharing is temporarily unavailable. Your video stays on this Mac.")
                            .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                        action(.init(title: "Try again", operation: .checking, enabled: true,
                            run: { Task { await controller.refresh() } }))
                    } else if !controller.isConnected {
                        signIn
                    } else if !controller.isSubscribed {
                        subscription
                    } else if isAccountOnly {
                        Text("Your videos are synced with this account.")
                            .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    } else if let url = currentShare, preparation == nil {
                        ready(url)
                    } else if let preparation {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("High quality · 1080p max", systemImage: "checkmark.shield")
                                .font(.system(size: 13, weight: .semibold))
                            Text(preparation.summary).font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                            Text("A smaller copy for sharing. Your original stays on this Mac.")
                                .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                        }
                        if case .failed(let error) = preparation.status { errorText(error) }
                        Button(action: preparation.export) {
                            Label("Create share link", systemImage: "link").frame(maxWidth: .infinity)
                        }.blitzButton(.accent).controlSize(.large)
                    } else if controller.fileURL != nil {
                        Button(action: controller.start) {
                            Text(controller.transferProgress == .processing ? "Check playback status"
                                 : controller.transferMessage == nil ? "Create share link" : "Resume upload")
                                .frame(maxWidth: .infinity)
                        }.blitzButton(.accent).controlSize(.large)
                    }
                    if preparation == nil, let message = controller.transferMessage { errorText(message) }
                    if let message = controller.accountMessage { errorText(message) }
                    if controller.isConnected {
                        if !isAccountOnly {
                            Button(action: showLibrary) {
                                Label("View shared videos", systemImage: "film.stack")
                                    .frame(maxWidth: .infinity)
                            }.blitzButton(.secondary)
                                .accessibilityLabel("View shared videos")
                                .help("Open your shared videos in Projects")
                        }
                        Divider()
                        account
                    }
                    if !isAccountOnly {
                    Text("Anyone with the link can watch. Transcript and chapters are included when available.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(BlitzUI.panelBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .controlSize(.regular)
        .task { await controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh() }
        }
        .onChange(of: controller.challenge?.challenge) {
            code = ""
            focusedField = controller.challenge == nil ? .email : .code
        }
        .onChange(of: controller.shareURL) { copied = false }
    }

    @ViewBuilder private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your BlitzRecorder account").font(.system(size: 13, weight: .semibold))
            if let challenge = controller.challenge {
                Text("Enter the code sent to \(challenge.email).")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("6-digit code", text: $code)
                    .textContentType(.oneTimeCode).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .code)
                    .accessibilityLabel("Email verification code")
                    .onChange(of: code) { code = String(code.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                    .onSubmit { if code.count == 6 { Task { await controller.verifyCode(code) } } }
                action(.init(title: "Continue", operation: .verifyingCode, enabled: code.count == 6,
                    run: { Task { await controller.verifyCode(code) } }))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(ceil(controller.resendAfter.timeIntervalSince(context.date))))
                    HStack {
                        Button(remaining > 0 ? "Resend in \(remaining)s" : "Resend code") {
                            Task { await controller.requestCode(email: challenge.email) }
                        }.disabled(remaining > 0 || controller.accountOperation != nil)
                        Spacer()
                        Button("Change email", action: controller.changeEmail)
                            .disabled(controller.accountOperation != nil)
                    }.blitzButton(.quiet).controlSize(.small)
                }
            } else {
                Text("Sign in or create an account with your email.")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .email)
                    .accessibilityLabel("BlitzRecorder email address")
                    .onSubmit { if email.contains("@") { Task { await controller.requestCode(email: email) } } }
                action(.init(title: "Continue with email", operation: .sendingCode, enabled: email.contains("@"),
                    run: { Task { await controller.requestCode(email: email) } }))
                Text("We’ll email you a sign-in code. No password needed.")
                    .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    @ViewBuilder private var subscription: some View {
        if let plan = controller.plan {
            VStack(alignment: .leading, spacing: 10) {
                Text("BlitzRecorder Hosting").font(.system(size: 15, weight: .semibold))
                Text("\(plan.price) / month").font(.system(size: 24, weight: .semibold))
                Text("Excluding tax · \(plan.allowance)")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                Text("High-quality sharing · Adaptive playback up to \(plan.maximumResolution)p")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                action(.init(title: controller.awaitingPayment ? "Reopen checkout" : "Enable sharing",
                    operation: .openingBilling, enabled: true, run: { Task { await controller.openBilling() } }))
                if controller.awaitingPayment { activity("Waiting for payment confirmation") }
                Text("Your local recordings and exports stay free. Hosted links require an active subscription.")
                    .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.account?.email ?? "BlitzRecorder account")
                .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            HStack {
                Text(controller.isSubscribed ? "Hosting active" : "Free account")
                    .font(.system(size: 11)).foregroundStyle(BlitzUI.supportingText)
                Spacer()
                if controller.isSubscribed {
                    Button("Manage") { Task { await controller.openBilling() } }
                        .blitzButton(.quiet).controlSize(.small)
                }
                Button(controller.accountOperation == .signingOut ? "Signing out…" : "Sign out") {
                    Task { await controller.disconnect() }
                }.blitzButton(.quiet).controlSize(.small)
            }.disabled(controller.accountOperation != nil || controller.isRunning || isSaving)
        }
    }

    private func ready(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ready to share", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(BlitzUI.mint)
            Text(url.absoluteString).font(.system(size: 12)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
            } label: {
                Label(copied ? "Link copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
                    .frame(maxWidth: .infinity)
            }.blitzButton(.accent).controlSize(.large)
            Button("Open watch page") { NSWorkspace.shared.open(url) }.blitzButton(.secondary)
            Button("Share current edit", action: newExport).blitzButton(.quiet)
        }
    }

    private struct Action {
        let title: String
        let operation: HostedVideoShareController.AccountOperation
        let enabled: Bool
        let run: () -> Void
    }

    private func action(_ action: Action) -> some View {
        Button(action: action.run) {
            HStack(spacing: 8) {
                if controller.accountOperation == action.operation { ProgressView().controlSize(.small) }
                Text(action.title)
            }.frame(maxWidth: .infinity)
        }
        .blitzButton(.accent).controlSize(.large)
        .disabled(!action.enabled || controller.accountOperation != nil)
    }

    private func activity(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(title).font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(BlitzUI.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct HostedVideoLinkActions: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
            } label: {
                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
            }.blitzButton(.secondary)
                .accessibilityLabel(copied ? "Link copied" : "Copy link")
                .help("Copy the watch link")
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open video", systemImage: "arrow.up.right")
            }.blitzButton(.quiet)
                .accessibilityLabel("Open shared video")
                .help("Open the shared video in your browser")
        }
        .onChange(of: url) { copied = false }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}

struct HostedVideoLibraryView: View {
    @Bindable var controller: HostedVideoShareController
    let showRecordings: () -> Void
    @State private var search = ""
    @State private var showsAccount = false

    private var matchingVideos: [HostedLibraryVideo] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return controller.videos.filter {
            query.isEmpty || $0.title.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shared videos").font(.system(size: 24, weight: .semibold))
                    Text("Your watch links, together in one place.")
                        .font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                }
                Spacer()
                if controller.isConnected {
                    Button { showsAccount.toggle() } label: {
                        Label("Account", systemImage: "person.crop.circle")
                    }.blitzButton(.quiet)
                    Button { Task { await controller.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }.blitzButton(.secondary)
                        .disabled(controller.accountOperation != nil || controller.isRefreshingVideos)
                }
            }.padding(24)

            if !controller.hasCheckedAccount {
                empty(.init(symbol: "icloud", title: "Loading your shared videos", detail: nil, loading: true))
            } else if !controller.isConnected || showsAccount {
                HostedVideoSharePanel(controller: controller, context: .account, preparation: nil,
                    newExport: {}, close: {}, showLibrary: {})
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsAccount {
                    Button("Back to shared videos") { showsAccount = false }
                        .blitzButton(.secondary).padding(24)
                }
            } else {
                library
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(BlitzUI.primaryText)
        .task { await controller.refresh() }
        .task(id: controller.videos.contains(where: \.isProcessing)) {
            guard controller.videos.contains(where: \.isProcessing) else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await controller.refreshVideos()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh() }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.isRunning, let progress = controller.transferProgress {
                HostedVideoProgressView(presentation: .transfer(progress))
                    .padding(.horizontal, 24).padding(.bottom, 20)
            }
            if !controller.isSubscribed {
                HStack {
                    Text("Your hosting plan is inactive. Enable it to make your watch links available again.")
                        .font(.system(size: 12)).foregroundStyle(BlitzUI.warning)
                    Spacer()
                    Button("Manage hosting") { showsAccount = true }.blitzButton(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            if let message = controller.libraryMessage ?? controller.accountMessage {
                HStack {
                    Text(message).font(.system(size: 12)).foregroundStyle(BlitzUI.warning)
                    Spacer()
                    Button("Retry") { Task { await controller.refreshVideos() } }
                        .blitzButton(.quiet).disabled(controller.isRefreshingVideos)
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(BlitzUI.secondaryText)
                TextField("Search shared videos", text: $search).textFieldStyle(.plain)
                    .accessibilityLabel("Search shared videos")
                Spacer()
                if controller.isRefreshingVideos {
                    ProgressView().controlSize(.small).accessibilityLabel("Syncing shared videos")
                }
                Text(matchingVideos.count == 1 ? "1 video" : "\(matchingVideos.count) videos")
                    .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
            }
            .padding(12)
            .background(BlitzUI.cardFill, in: .rect(cornerRadius: 8))
            .padding(.horizontal, 24).padding(.bottom, 16)

            if controller.videos.isEmpty && controller.isRefreshingVideos && controller.libraryUpdatedAt == nil {
                empty(.init(symbol: "icloud", title: "Loading shared videos", detail: nil, loading: true))
            } else if controller.videos.isEmpty && controller.libraryMessage == nil {
                empty(.init(symbol: "link", title: "Your next video belongs here",
                    detail: "Open a recording, then choose Share to create its watch page.", loading: false,
                    action: .init(title: "Choose a recording", run: showRecordings)))
            } else if controller.videos.isEmpty, controller.libraryMessage != nil {
                empty(.init(symbol: "wifi.exclamationmark", title: "Shared videos unavailable",
                    detail: "Refresh when your connection is back.", loading: false))
            } else if matchingVideos.isEmpty {
                empty(.init(symbol: "magnifyingglass", title: "No matching videos",
                    detail: "Try another title.", loading: false))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(matchingVideos) { video in
                            row(video)
                            Divider().padding(.leading, 66)
                        }
                    }.padding(.horizontal, 24)
                }
                HStack {
                    if let date = controller.libraryUpdatedAt {
                        Text("Synced \(date.formatted(date: .omitted, time: .shortened))")
                    }
                    Spacer()
                    Text(controller.account?.email ?? "")
                }
                .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText).padding(24)
            }
        }
    }

    private func row(_ video: HostedLibraryVideo) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                videoLabel(video)
                Spacer(minLength: 12)
                videoActions(video)
            }
            VStack(alignment: .leading, spacing: 12) {
                videoLabel(video)
                videoActions(video).padding(.leading, 52)
            }
        }
        .padding(.vertical, 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(video.title)
    }

    private func videoLabel(_ video: HostedLibraryVideo) -> some View {
        HStack(spacing: 14) {
            Image(systemName: video.status == "ready" ? "play.rectangle" : "film")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(video.status == "ready" ? BlitzUI.mint : BlitzUI.secondaryText)
                .frame(width: 38, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(video.title).font(.system(size: 14, weight: .semibold))
                    .lineLimit(2).help(video.title)
                HStack(spacing: 8) {
                    if video.isProcessing { ProgressView().controlSize(.mini) }
                    Text(video.statusLabel)
                        .foregroundStyle(video.status == "failed" ? BlitzUI.warning : BlitzUI.supportingText)
                    if let duration = video.duration, duration.isFinite, duration > 0 {
                        Text("·").accessibilityHidden(true)
                        Text(SilenceTime.label(duration))
                    }
                    if let width = video.width, let height = video.height {
                        Text("·").accessibilityHidden(true)
                        Text("\(width) × \(height)")
                    }
                }.font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                if let error = video.error, video.status == "failed" {
                    Text(error).font(.system(size: 11)).foregroundStyle(BlitzUI.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if video.status == "uploading" {
                    Text("Resume from the Share panel of the original recording.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                }
            }
        }
    }

    @ViewBuilder private func videoActions(_ video: HostedLibraryVideo) -> some View {
        if let url = controller.watchURL(video) {
            HostedVideoLinkActions(url: url).controlSize(.regular)
                .disabled(!controller.isSubscribed)
        }
    }

    private struct Empty {
        struct Action {
            let title: String
            let run: () -> Void
        }
        let symbol: String
        let title: String
        let detail: String?
        let loading: Bool
        var action: Action? = nil
    }

    private func empty(_ content: Empty) -> some View {
        VStack(spacing: 12) {
            if content.loading { ProgressView().controlSize(.regular) }
            else {
                Image(systemName: content.symbol).font(.system(size: 32, weight: .light))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            Text(content.title).font(.system(size: 17, weight: .semibold))
            if let detail = content.detail {
                Text(detail).font(.system(size: 13)).foregroundStyle(BlitzUI.supportingText)
                    .multilineTextAlignment(.center)
            }
            if let action = content.action {
                Button(action.title, action: action.run)
                    .blitzButton(.accent).controlSize(.large).padding(.top, 8)
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
