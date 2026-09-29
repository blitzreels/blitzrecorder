import AppKit
import SwiftUI

struct HostedVideoSharePanel: View {
    enum Context {
        case project(path: String?, title: String)
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
    @FocusState private var focusedField: Field?
    private enum Field { case email, code }

    private var isAccountOnly: Bool {
        if case .account = context { return true }
        return false
    }

    private var previousShare: URL? {
        guard case .project(let path, _) = context else { return nil }
        return controller.sharedURL(forProject: path)
    }

    private var currentShare: URL? {
        guard case .project(let path, _) = context, let path else { return nil }
        return controller.projectPath == path ? controller.shareURL ?? previousShare : previousShare
    }

    private var projectTitle: String {
        guard case .project(_, let title) = context else { return "" }
        return title
    }

    private var isSaving: Bool {
        if case .exporting = preparation?.status { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !isAccountOnly {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Share video")
                                .font(BlitzType.title)
                            Text(projectTitle)
                                .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Button(action: close) {
                            Image(systemName: "xmark").frame(width: 14, height: 14)
                        }
                        .blitzButton(.quiet).controlSize(.small)
                        .accessibilityLabel("Close sharing")
                        .help("Back to editing. Sharing continues in the background.")
                    }
                }
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.18), value: stateKey)
                if !isAccountOnly {
                    Text("Anyone with the link can watch. Transcript and chapters are included when available.")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isAccountOnly, let url = previousShare, preparation != nil || controller.isRunning || isSaving {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previously shared")
                            .font(BlitzType.strong).foregroundStyle(BlitzUI.secondaryText)
                        HostedVideoLinkField(url: url, prominence: .secondary)
                        Text("That link keeps the version you shared. Sharing now creates a new link.")
                            .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
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
    }

    private enum StateKey: Hashable {
        case uploading, saving, loading, unavailable, signIn, subscribe, account, ready, prepare, resume, idle
    }

    private var stateKey: StateKey {
        if !isAccountOnly, controller.isRunning, controller.transferProgress != nil { return .uploading }
        if !isAccountOnly, isSaving { return .saving }
        if !controller.hasCheckedAccount { return .loading }
        if controller.plan == nil || controller.plan?.available == false { return .unavailable }
        if !controller.isConnected { return .signIn }
        if !controller.isSubscribed { return .subscribe }
        if isAccountOnly { return .account }
        if currentShare != nil, preparation == nil { return .ready }
        if preparation != nil { return .prepare }
        if controller.fileURL != nil { return .resume }
        return .idle
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch stateKey {
            case .uploading:
                if let progress = controller.transferProgress {
                    HostedVideoProgressView(presentation: .transfer(progress))
                    HStack {
                        Text("Keep editing while your video is prepared.")
                            .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                        Spacer(minLength: 8)
                        if progress != .processing {
                            Button(action: controller.pause) { Label("Pause", systemImage: "pause.fill") }
                                .blitzButton(.secondary).controlSize(.small)
                        }
                    }
                }
            case .saving:
                if let preparation, case .exporting(let progress) = preparation.status {
                    HostedVideoProgressView(presentation: .exporting(progress))
                }
            case .loading:
                placeholder
            case .unavailable:
                Text("Sharing is temporarily unavailable. Your video stays on this Mac.")
                    .font(BlitzType.callout).foregroundStyle(BlitzUI.supportingText)
                action(.init(title: "Try again", operation: .checking, enabled: true,
                    run: { Task { await controller.refresh() } }))
            case .signIn:
                signIn
            case .subscribe:
                subscription
            case .account:
                Label("Your videos are synced with this account.", systemImage: "checkmark.circle.fill")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
            case .ready:
                if let url = currentShare { ready(url) }
            case .prepare:
                if let preparation {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("High quality, up to 1080p", systemImage: "checkmark.shield.fill")
                            .font(BlitzType.section)
                        Text("\(preparation.summary) · Your original stays on this Mac.")
                            .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if case .failed(let error) = preparation.status { errorText(error) }
                    Button(action: preparation.export) {
                        Label("Create share link", systemImage: "link").frame(maxWidth: .infinity)
                    }.blitzButton(.accent).controlSize(.large)
                }
            case .resume:
                Button(action: controller.start) {
                    Text(controller.transferProgress == .processing ? "Check playback status"
                         : controller.transferMessage == nil ? "Create share link" : "Resume upload")
                        .frame(maxWidth: .infinity)
                }.blitzButton(.accent).controlSize(.large)
            case .idle:
                EmptyView()
            }
            if preparation == nil, let message = controller.transferMessage { errorText(message) }
            if [.uploading, .ready].contains(stateKey), let notice = controller.detailsNotice {
                Label(notice, systemImage: "text.badge.xmark")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = controller.accountMessage { errorText(message) }
        }
        .transition(.opacity)
        .id(stateKey)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(BlitzUI.controlFill).frame(width: 150, height: 12)
            RoundedRectangle(cornerRadius: 3).fill(BlitzUI.quietFill).frame(maxWidth: .infinity).frame(height: 10)
            RoundedRectangle(cornerRadius: BlitzControlMetrics.radius).fill(BlitzUI.quietFill)
                .frame(height: BlitzControlMetrics.height(.large))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your BlitzRecorder account")
    }

    @ViewBuilder private var footer: some View {
        if controller.isConnected {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.account?.email ?? "BlitzRecorder account")
                        .font(BlitzType.label).lineLimit(1).truncationMode(.middle)
                    Text(controller.isSubscribed ? "Hosting active" : "Free account")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                Spacer(minLength: 8)
                BlitzGlassMenu(entries: accountEntries, menuWidth: 200) {
                    Image(systemName: "ellipsis")
                        .font(BlitzType.glyph(12))
                        .foregroundStyle(BlitzUI.supportingText)
                        .frame(width: 28, height: BlitzControlMetrics.height(.small))
                        .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
                }
                .accessibilityLabel("Account options")
                .help("Account options")
                .disabled(controller.accountOperation != nil || controller.isRunning || isSaving)
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(BlitzUI.separator).frame(height: 1) }
        }
    }

    private var accountEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        if !isAccountOnly {
            entries.append(.item(.init(title: "All shared videos", systemImage: "film.stack.fill", action: showLibrary)))
        }
        if controller.isSubscribed {
            entries.append(.item(.init(title: "Manage hosting", systemImage: "creditcard.fill",
                action: { Task { await controller.openBilling() } })))
        }
        if !entries.isEmpty { entries.append(.divider) }
        entries.append(.item(.init(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right",
            isDestructive: true, action: { Task { await controller.disconnect() } })))
        return entries
    }

    @ViewBuilder private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isAccountOnly ? "Sign in" : "Sign in to share").font(BlitzType.section)
            if let challenge = controller.challenge {
                Text("Enter the code sent to \(challenge.email).")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
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
                    }.blitzButton(.quiet).controlSize(.small).monospacedDigit()
                }
            } else {
                Text("Sign in or create an account with your email.")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress).textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .email)
                    .accessibilityLabel("BlitzRecorder email address")
                    .onSubmit { if email.contains("@") { Task { await controller.requestCode(email: email) } } }
                action(.init(title: "Continue with email", operation: .sendingCode, enabled: email.contains("@"),
                    run: { Task { await controller.requestCode(email: email) } }))
                Text("We’ll email you a sign-in code. No password needed.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    @ViewBuilder private var subscription: some View {
        if let plan = controller.plan {
            VStack(alignment: .leading, spacing: 10) {
                Text("BlitzRecorder Hosting").font(BlitzType.title)
                Text("\(plan.price) / month").font(BlitzType.largeTitle)
                Text("Excluding tax · \(plan.allowance)")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                Text("High-quality sharing · Adaptive playback up to \(plan.maximumResolution)p")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                action(.init(title: controller.awaitingPayment ? "Reopen checkout" : "Enable sharing",
                    operation: .openingBilling, enabled: true, run: { Task { await controller.openBilling() } }))
                if controller.awaitingPayment { activity("Waiting for payment confirmation") }
                Text("Your local recordings and exports stay free. Hosted links require an active subscription.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
        }
    }

    private func ready(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Watch link")
                    .font(BlitzType.strong).foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 8)
                Circle().fill(BlitzUI.mint).frame(width: 6, height: 6)
                Text("Live").font(BlitzType.captionEmphasis).foregroundStyle(BlitzUI.supportingText)
            }
            .accessibilityElement(children: .combine)
            Text(HostedVideoLinkField.displayText(url))
                .font(BlitzType.callout)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(1).truncationMode(.tail)
                .textSelection(.enabled)
                .help(url.absoluteString)
            HostedVideoCopyLinkButton(url: url)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { readyActions(url) }
                VStack(spacing: 8) { readyActions(url) }
            }
        }
        .padding(14)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
    }

    @ViewBuilder private func readyActions(_ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label("Open", systemImage: "safari.fill").frame(maxWidth: .infinity)
        }
        .blitzButton(.secondary)
        .help("Open the watch page in your browser")
        Button(action: newExport) {
            Label("New link", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                .lineLimit(1)
        }
        .blitzButton(.secondary)
        .help("Share your latest edit as a new link. The current link keeps its version.")
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
            Text(title).font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(BlitzType.body).foregroundStyle(BlitzUI.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}
