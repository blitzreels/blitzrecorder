import AppKit
import SwiftUI

struct HostedVideoSharePanel: View {
    struct ProjectContext {
        let path: String?
        let title: String
        let exports: [RecordingProject.ExportRecord]
        let shareFile: (URL) -> Void
    }
    enum Context {
        case project(ProjectContext)
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
    @State private var stopping: HostedLibraryVideo?

    private var isAccountOnly: Bool {
        if case .account = context { return true }
        return false
    }

    private var project: ProjectContext? {
        guard case .project(let project) = context else { return nil }
        return project
    }

    private var previousShare: URL? {
        controller.sharedURL(forProject: project?.path)
    }

    private var currentShare: URL? {
        guard let path = project?.path else { return nil }
        return controller.projectPath == path ? controller.shareURL ?? previousShare : previousShare
    }

    private var projectTitle: String { project?.title ?? "" }

    private var isSaving: Bool {
        if case .exporting = preparation?.status { return true }
        return false
    }

    var body: some View {
        Group {
            if isAccountOnly {
                stack
            } else {
                ScrollView {
                    stack
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                .background(BlitzUI.panelBackground)
            }
        }
        .foregroundStyle(BlitzUI.primaryText)
        .controlSize(.regular)
        .task { await controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh() }
        }
        .confirmationDialog("Stop sharing this link?", isPresented: Binding(
            get: { stopping != nil }, set: { if !$0 { stopping = nil } }), presenting: stopping) { video in
            Button("Stop sharing", role: .destructive) { Task { await controller.stopSharing(video) } }
        } message: { video in
            Text(video.isOwnStorage
                 ? "The link stops working and the video is deleted from your Cloudflare. Your recording stays on this Mac."
                 : "The link stops working for everyone and the video is deleted from BlitzRecorder Hosting. Your recording stays on this Mac.")
        }
    }

    private func liveVideo(_ url: URL) -> HostedLibraryVideo? {
        controller.links(forProject: project?.path).first { $0.url == url }?.video
    }

    private var stack: some View {
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
                    .animation(.easeOut(duration: 0.12), value: stateKey)
                if !isAccountOnly {
                    Text("Anyone with the link can watch. Transcript and chapters are included when available.")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let project {
                    HostedVideoShareHistory(controller: controller, configuration: .init(
                        links: controller.links(forProject: project.path),
                        featuredLink: stateKey == .ready ? currentShare : nil,
                        exports: project.exports.reversed(),
                        linksNote: preparation != nil
                            ? "Each link keeps the version you shared. Sharing now creates a new link." : nil,
                        canShareFile: controller.canShare && !controller.isRunning && !isSaving,
                        shareFile: project.shareFile
                    ))
                }
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum StateKey: Hashable {
        case uploading, saving, loading, unavailable, signIn, choosePlan, account, ready, prepare, resume, idle
    }

    /// A paused or failed upload whose file is still on disk. A finished link that was stopped is not
    /// resumable: sharing again starts from the current edit.
    private var hasResumableUpload: Bool {
        guard let fileURL = controller.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        return controller.transferMessage != nil
    }

    private var stateKey: StateKey {
        if !isAccountOnly, controller.isRunning, controller.transferProgress != nil { return .uploading }
        if !isAccountOnly, isSaving { return .saving }
        if !controller.hasCheckedAccount { return .loading }
        if controller.plan?.offersSharing != true { return .unavailable }
        if !controller.isConnected { return .signIn }
        if !controller.canShare { return .choosePlan }
        if isAccountOnly { return .account }
        if currentShare != nil, preparation == nil { return .ready }
        if preparation != nil { return .prepare }
        if hasResumableUpload { return .resume }
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
                        if !progress.isProcessing {
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
            case .choosePlan:
                if let plan = controller.plan { HostedSharingPlanPicker(controller: controller, plan: plan) }
            case .account:
                Label("Your videos are synced with this account.", systemImage: "checkmark.circle.fill")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                HostedSharingStorageSummary(controller: controller)
            case .ready:
                if let url = currentShare { ready(url) }
            case .prepare:
                if let preparation {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("High quality, up to 1080p", systemImage: "checkmark.shield")
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
                    Text(controller.transferProgress?.isProcessing == true ? "Check playback status"
                         : controller.transferMessage == nil ? "Create share link" : "Resume upload")
                        .frame(maxWidth: .infinity)
                }.blitzButton(.accent).controlSize(.large)
            case .idle:
                Button(action: newExport) {
                    Label("Create share link", systemImage: "link").frame(maxWidth: .infinity)
                }.blitzButton(.accent).controlSize(.large)
            }
            if preparation == nil, let message = controller.transferMessage { errorText(message) }
            if [.uploading, .ready].contains(stateKey), let notice = controller.detailsNotice {
                Label(notice, systemImage: "text.badge.xmark")
                    .font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stateKey != .signIn, let message = controller.accountMessage { errorText(message) }
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
                    Text(storageLabel)
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
                Spacer(minLength: 8)
                BlitzInlineActions(entries: accountEntries)
                .controlSize(.small)
                .disabled(controller.accountOperation != nil || controller.isRunning || isSaving)
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(BlitzUI.separator).frame(height: 1) }
        }
    }

    private var storageLabel: String {
        switch controller.activeStorage {
        case .blitzrecorder: "BlitzRecorder Hosting"
        case .cloudflare: "Sharing from your Cloudflare"
        case nil: "Free account"
        }
    }

    private var accountEntries: [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        if !isAccountOnly {
            entries.append(.item(.init(title: "All shared videos", systemImage: "film.stack", action: showLibrary)))
        }
        if controller.isSubscribed {
            entries.append(.item(.init(title: "Manage hosting", systemImage: "creditcard",
                action: { Task { await controller.openBilling() } })))
        }
        entries.append(.item(.init(title: "Sign out", systemImage: "rectangle.portrait.and.arrow.right",
            isDestructive: true, action: { Task { await controller.disconnect() } })))
        return entries
    }

    @ViewBuilder private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isAccountOnly {
                Text("Sign in to share").font(BlitzType.section)
            }
            HostedSignInForm(controller: controller, layout: .leading)
        }
    }

    private func ready(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Your link is live")
                    .font(BlitzType.strong).foregroundStyle(BlitzUI.secondaryText)
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .combine)
            Text(HostedVideoLinkField.displayText(url))
                .font(BlitzType.callout)
                .foregroundStyle(BlitzUI.primaryText)
                .lineLimit(1).truncationMode(.tail)
                .textSelection(.enabled)
                .help(url.absoluteString)
            BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy link", emphasis: .accent, width: .fill)))
                .controlSize(.large)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { readyActions(url) }
                VStack(spacing: 8) { readyActions(url) }
            }
            if let video = liveVideo(url) {
                Button("Stop sharing…") { stopping = video }
                    .blitzButton(.quiet)
                    .controlSize(.small)
                    .foregroundStyle(BlitzUI.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(controller.changingVideos.contains(video.id))
                    .help("Turn this link off and delete the hosted copy. Your files on this Mac stay.")
            }
        }
        .padding(14)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
    }

    @ViewBuilder private func readyActions(_ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label("Open", systemImage: "safari").frame(maxWidth: .infinity)
        }
        .blitzButton(.secondary)
        .help("Open the watch page in your browser")
        Button(action: newExport) {
            Label("Share latest edit", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                .lineLimit(1)
        }
        .blitzButton(.secondary)
        .help("Export your current edit and share it as a new link. This link keeps the version it has now.")
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
