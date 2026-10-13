import AppKit
import SwiftUI

/// Two ways to turn on share links: our paid hosting, or free with the user's own Cloudflare account.
struct HostedSharingPlanPicker: View {
    @Bindable var controller: HostedVideoShareController
    let plan: HostingPlan
    @State private var connecting = false
    @State private var token = ""
    @FocusState private var tokenFocused: Bool

    private var offersBoth: Bool { plan.available && plan.ownStorage == true }
    private var showsConnect: Bool { connecting || !plan.available }
    private var tokenIsPlausible: Bool { token.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsConnect {
                connect.transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                choices.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.15), value: showsConnect)
        .animation(.easeOut(duration: 0.12), value: controller.cloudflareStep)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where should shared videos live?").font(BlitzType.section)
            VStack(spacing: 6) {
                row(.init(symbol: "play.rectangle", title: "BlitzRecorder Hosting",
                          detail: "\(plan.storageBytes / 1_000_000_000) GB · nothing to set up",
                          price: plan.price, unit: "/mo", busy: controller.accountOperation == .openingBilling)) {
                    Task { await controller.openBilling() }
                }
                if plan.ownStorage == true {
                    row(.init(symbol: "cloud", title: "Your Cloudflare",
                              detail: "10 GB free, then cents per GB", price: "Free", unit: "", busy: false)) {
                        connecting = true
                        tokenFocused = true
                    }
                }
            }
            .disabled(controller.accountOperation != nil)
            if controller.awaitingPayment {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for payment").font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                    Spacer(minLength: 8)
                    Button("Reopen") { Task { await controller.openBilling() } }
                        .blitzButton(.quiet).controlSize(.small)
                }
            }
        }
    }

    private struct Row {
        let symbol: String
        let title: String
        let detail: String
        let price: String
        let unit: String
        let busy: Bool
    }

    private func row(_ row: Row, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: row.symbol)
                    .font(BlitzType.symbol(14))
                    .foregroundStyle(BlitzUI.supportingText)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(BlitzType.strong).foregroundStyle(BlitzUI.primaryText)
                    Text(row.detail).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 8)
                if row.busy {
                    ProgressView().controlSize(.small)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(row.price).font(BlitzType.strong).foregroundStyle(BlitzUI.primaryText)
                        Text(row.unit).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    }
                    .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(BlitzType.symbol(10))
                    .foregroundStyle(BlitzUI.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: BlitzControlMetrics.detailedRowHeight - 10)
            .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.controlRadius))
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: false))
    }

    @ViewBuilder private var connect: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                if offersBoth {
                    Button {
                        controller.cancelCloudflareSetup()
                        connecting = false
                    } label: {
                        Image(systemName: "chevron.left").font(BlitzType.symbol(11)).frame(width: 22, height: 22)
                    }
                    .blitzButton(.quiet).controlSize(.small)
                    .accessibilityLabel("Back to plans")
                }
                Text("Connect Cloudflare").font(BlitzType.section)
            }
            if let step = controller.cloudflareStep {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(CloudflareSetupStep.allCases, id: \.self) { item in setupRow(item, current: step) }
                }
                Button("Cancel", action: controller.cancelCloudflareSetup)
                    .blitzButton(.quiet).controlSize(.small)
            } else {
                Text("Free from us. Cloudflare includes 10 GB, then charges about 1.5 cents per GB a month.")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
                Button { NSWorkspace.shared.open(CloudflareSetup.tokenTemplateURL) } label: {
                    Label("Create a token in Cloudflare", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
                }
                .blitzButton(.secondary)
                .help("Opens Cloudflare with the right permissions filled in. Click Continue, then Create Token.")
                HStack(spacing: 8) {
                    SecureField("Paste the token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .focused($tokenFocused)
                        .accessibilityLabel("Cloudflare API token")
                        .onSubmit { if tokenIsPlausible { controller.connectCloudflare(token: token) } }
                    Button("Connect") { controller.connectCloudflare(token: token) }
                        .blitzButton(tokenIsPlausible ? .accent : .secondary)
                        .disabled(!tokenIsPlausible)
                }
                if let failure = controller.cloudflareFailure {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(failure.message).font(BlitzType.body).foregroundStyle(BlitzUI.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = failure.fixURL, let title = failure.fixTitle {
                            Spacer(minLength: 4)
                            Button(title) { NSWorkspace.shared.open(url) }
                                .blitzButton(.quiet).controlSize(.small).fixedSize()
                        }
                    }
                }
                Text("We set up storage and a video player in your account. The token stays in your Keychain.")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupRow(_ item: CloudflareSetupStep, current: CloudflareSetupStep) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if item.rawValue < current.rawValue {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BlitzUI.accent)
                } else if item == current {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "circle").foregroundStyle(BlitzUI.tertiaryText)
                }
            }
            .font(BlitzType.symbol(13))
            .frame(width: 18, height: 18)
            Text(item.title).font(BlitzType.body)
                .foregroundStyle(item.rawValue <= current.rawValue ? BlitzUI.primaryText : BlitzUI.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Where new links upload, and the way out of Cloudflare, for users who already share.
struct HostedSharingStorageSummary: View {
    @Bindable var controller: HostedVideoShareController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.isSubscribed, controller.cloudflare != nil {
                BlitzSegmentedPicker(configuration: .init(
                    title: "New links",
                    options: [HostedVideoShareController.Storage.blitzrecorder, .cloudflare],
                    selection: Binding(get: { controller.preferredStorage }, set: { controller.useStorage($0) }),
                    label: { $0 == .blitzrecorder ? "BlitzRecorder" : "My Cloudflare" },
                    symbolName: { $0 == .blitzrecorder ? "play.rectangle" : "cloud" },
                    help: { _ in "Where new share links upload" }))
                .disabled(controller.isRunning)
            }
            if let cloudflare = controller.cloudflare {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Cloudflare · \(cloudflare.accountName)").font(BlitzType.label).lineLimit(1)
                        Text(cloudflare.displayHost).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Disconnect", action: controller.forgetCloudflare)
                        .blitzButton(.quiet).controlSize(.small)
                        .disabled(controller.isRunning)
                        .help("New links stop using Cloudflare. Links you already shared keep playing.")
                }
            }
        }
    }
}

#Preview("Plan picker") {
    HostedSharingPlanPicker(controller: .shared, plan: .init(
        name: "BlitzRecorder Hosting", amount: 900, currency: "eur", storageBytes: 50_000_000_000, uploadSeconds: 18_000,
        uploadWindowDays: 30, maximumResolution: 1080, retentionDaysAfterExpiry: 30, available: true, ownStorage: true))
        .padding(20)
        .frame(width: 320)
        .background(BlitzUI.panelBackground)
        .preferredColorScheme(.dark)
}
