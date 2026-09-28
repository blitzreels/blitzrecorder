import AppKit
import SwiftUI

struct HostedVideoSharePanel: View {
    struct ExportPreparation {
        let title: String
        let summary: String
        let status: EditorExportStatus?
        let export: () -> Void
    }

    @Bindable var controller: HostedVideoShareController
    let preparation: ExportPreparation?
    let newExport: () -> Void
    let close: () -> Void
    @State private var email = ""
    @State private var code = ""
    @State private var copied = false
    @FocusState private var focusedField: Field?
    private enum Field { case email, code }

    private var isSaving: Bool {
        if case .exporting = preparation?.status { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: close) { Image(systemName: "arrow.left") }
                    .blitzButton(.quiet).controlSize(.small)
                    .accessibilityLabel("Back to editing")
                    .help("Back to editing. Sharing continues in the background.")
                Text("Share video").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(controller.isRunning ? controller.fileURL?.lastPathComponent ?? "Video"
                             : preparation?.title ?? controller.fileURL?.lastPathComponent ?? "Your video")
                            .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        Text("A watch page on BlitzRecorder, ready to share.")
                            .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    }
                    if controller.isRunning, let progress = controller.transferProgress {
                        HostedVideoProgressView(presentation: .transfer(progress))
                        if progress != .processing {
                            Button("Pause upload", action: controller.pause).blitzButton(.secondary)
                        }
                        Text("You can keep editing while your video is prepared.")
                            .font(.system(size: 12)).foregroundStyle(BlitzUI.supportingText)
                    } else if isSaving, let preparation, case .exporting(let progress) = preparation.status {
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
                    } else if let url = controller.shareURL, preparation == nil {
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
                        Divider()
                        account
                    }
                    Text("Anyone with the link can watch. Transcript and chapters are included when available.")
                        .font(.system(size: 11)).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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
