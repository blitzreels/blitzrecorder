import AppKit
import SwiftUI

struct HostedVideoLibraryView: View {
    @Bindable var controller: HostedVideoShareController
    let showRecordings: () -> Void
    let thumbnail: (HostedLibraryVideo) -> NSImage?
    let showcase: [HostedSharingShowcaseItem]
    @State private var search = ""
    @State private var showsAccount = false
    @State private var stopping: HostedLibraryVideo?

    private var matchingVideos: [HostedLibraryVideo] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return controller.videos.filter {
            query.isEmpty || $0.title.localizedStandardContains(query)
        }
    }

    private var isLoading: Bool {
        !controller.hasCheckedAccount
            || (controller.isConnected && controller.videos.isEmpty && controller.libraryUpdatedAt == nil
                && controller.libraryMessage == nil)
    }

    private var isSyncing: Bool {
        controller.isRefreshingVideos || controller.accountOperation == .checking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.hasCheckedAccount && !controller.isConnected {
                HostedSharingWelcome(controller: controller, showcase: showcase)
            } else {
                header
                library
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(BlitzUI.primaryText)
        .stopSharingConfirmation(.init(stopping: $stopping, controller: controller,
                                       title: "Stop sharing “\(stopping?.title ?? "")”?",
                                       hostedMessage: "The link stops working for everyone. Your recording stays on this Mac."))
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

    private var header: some View {
        BlitzAdaptiveRow(.init(minimumContentWidth: 300)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared videos").font(BlitzType.largeTitle)
                Text("Your watch links, together in one place.")
                    .font(BlitzType.callout).foregroundStyle(BlitzUI.supportingText)
            }
            if controller.isConnected {
                if controller.libraryMessage != nil, !controller.videos.isEmpty {
                    Text(controller.libraryUpdatedAt.map { "Offline · synced \($0.formatted(date: .omitted, time: .shortened))" }
                         ?? "Offline")
                        .font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                        .help("Couldn’t refresh. Showing your last synced videos.")
                }
                Button { Task { await controller.refresh() } } label: {
                    ZStack {
                        ProgressView().controlSize(.small).opacity(isSyncing ? 1 : 0)
                        Image(systemName: "arrow.clockwise").opacity(isSyncing ? 0 : 1)
                    }
                    .frame(width: 16, height: 16)
                }
                .blitzButton(.quiet)
                .disabled(isSyncing)
                .accessibilityLabel(isSyncing ? "Syncing shared videos" : "Refresh shared videos")
                .help(syncedHelp)
                Button { showsAccount.toggle() } label: {
                    Label(controller.account?.email ?? "Account", systemImage: "person.crop.circle")
                        .lineLimit(1)
                        .frame(maxWidth: 220)
                        .help(controller.account?.email ?? "Account")
                }
                .blitzButton(.secondary)
                .accessibilityLabel("Account")
                .popover(isPresented: $showsAccount, arrowEdge: .bottom) {
                    HostedAccountPopover(controller: controller)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
    }

    private var syncedHelp: String {
        guard let date = controller.libraryUpdatedAt else { return "Refresh" }
        return "Synced \(date.formatted(date: .omitted, time: .shortened))"
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            notice
            searchField
            if isLoading {
                BlitzLoadingState(title: "Loading shared videos")
            } else if controller.videos.isEmpty && controller.libraryMessage == nil {
                empty(.init(symbol: BlitzSymbols.share, title: "Your next video belongs here",
                    detail: "Open a recording, then choose Share to create its watch page.",
                    action: .init(title: "Choose a recording", run: showRecordings)))
            } else if controller.videos.isEmpty {
                empty(.init(symbol: "wifi.slash", title: "Can’t reach your shared videos",
                    detail: "Check your connection, then try again.",
                    action: .init(title: "Try again", run: { Task { await controller.refresh() } })))
            } else if matchingVideos.isEmpty {
                empty(.init(symbol: "magnifyingglass", title: "No matching videos",
                    detail: "Try another title.", action: nil))
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 20) {
                        ForEach(matchingVideos) { video in
                            card(video)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    @ViewBuilder private var notice: some View {
        if controller.isRunning, let progress = controller.transferProgress {
            HostedVideoProgressView(presentation: .transfer(progress))
                .padding(14)
                .background(BlitzUI.cardFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
                .padding(.horizontal, 24)
        } else if !controller.isSubscribed, controller.isConnected, controller.videos.contains(where: { !$0.isOwnStorage }) {
            noticeRow(.init(symbol: "pause.circle",
                text: "Your hosting plan is off, so these links don’t play right now.",
                action: .init(title: "Turn on", run: { showsAccount = true })))
        }
    }

    private struct Notice {
        let symbol: String
        let text: String
        let action: BlitzEmptyState.Action
    }

    private func noticeRow(_ notice: Notice) -> some View {
        BlitzAdaptiveRow() {
            HStack(spacing: 10) {
                Image(systemName: notice.symbol).foregroundStyle(BlitzUI.secondaryText)
                Text(notice.text).font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(notice.action.title, action: notice.action.run)
                .blitzButton(.secondary).controlSize(.small)
                .disabled(isSyncing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(BlitzUI.quietFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
        .padding(.horizontal, 24)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(BlitzUI.secondaryText)
            TextField("Search shared videos", text: $search).textFieldStyle(.plain)
                .accessibilityLabel("Search shared videos")
            Text(isLoading ? " " : matchingVideos.count == 1 ? "1 video" : "\(matchingVideos.count) videos")
                .font(BlitzType.body.monospacedDigit()).foregroundStyle(BlitzUI.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: BlitzControlMetrics.height(.regular))
        .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzControlMetrics.radius))
        .padding(.horizontal, 24)
        .disabled(isLoading)
    }

    private static let gridColumns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 20, alignment: .top)]

    private func card(_ video: HostedLibraryVideo) -> some View {
        let url = controller.watchURL(video)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: BlitzUI.cardRadius).fill(BlitzUI.controlFill)
                if let image = thumbnail(video) {
                    Color.clear.overlay {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    }
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(BlitzType.glyph(28))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                if video.isProcessing {
                    Color.black.opacity(0.45)
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(BlitzUI.onMediaText)
                        Text(video.statusLabel).font(BlitzType.captionEmphasis)
                    }
                    .foregroundStyle(BlitzUI.onMediaText)
                } else if video.status == "failed" {
                    Color.black.opacity(0.45)
                    Label(video.statusLabel, systemImage: "exclamationmark.triangle.fill")
                        .font(BlitzType.captionEmphasis).foregroundStyle(BlitzUI.warning)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
            .contentShape(.rect(cornerRadius: BlitzUI.cardRadius))
            .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
            .help(url == nil ? video.statusLabel : "Open the watch page")

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(BlitzType.strong).lineLimit(1).help(video.title)
                Text(detail(video))
                    .font(BlitzType.caption.monospacedDigit())
                    .foregroundStyle(video.status == "failed" ? BlitzUI.warning : BlitzUI.secondaryText)
                    .lineLimit(1)
                    .help(video.error ?? "")
            }
            HStack(spacing: 8) {
                if let url {
                    HStack(spacing: 8) {
                        BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy link", emphasis: .secondary, width: .fixed(84))))
                        Button { NSWorkspace.shared.open(url) } label: {
                            Label("Open", systemImage: BlitzSymbols.openLink)
                        }
                        .blitzButton(.secondary)
                        .help("Open the watch page in your browser")
                    }
                    .fixedSize()
                    .disabled(!video.isShared)
                }
                Spacer(minLength: 0)
                if video.status == "ready" {
                    publicSwitch(video)
                }
            }
            .controlSize(.small)
            .disabled(!controller.isSubscribed && !video.isOwnStorage)
            .frame(height: BlitzControlMetrics.height(.small), alignment: .leading)
        }
        .contentShape(.rect)
        .contextMenu {
            if ["ready", "failed", "queued", "processing"].contains(video.status) {
                BlitzContextMenuItems(entries: videoEntries(video))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(video.title)
    }

    private func publicSwitch(_ video: HostedLibraryVideo) -> some View {
        Toggle("Public", isOn: Binding(
            get: { video.listed != false },
            set: { listed in Task { await controller.setListed(.init(video: video, listed: listed)) } }
        ))
        .toggleStyle(.blitzSwitch)
        .font(BlitzType.label)
        .foregroundStyle(BlitzUI.supportingText)
        .fixedSize()
        .disabled(controller.changingVideos.contains(video.id))
        .help(video.listed != false
              ? "Anyone with the link can watch. Turn off to hide the link without deleting it."
              : "The link is hidden. Turn on so anyone with the link can watch.")
    }

    private func videoEntries(_ video: HostedLibraryVideo) -> [BlitzMenuEntry] {
        var entries: [BlitzMenuEntry] = []
        if video.status == "ready" {
            let listed = video.listed != false
            entries.append(.item(.init(title: listed ? "Hide link" : "Show link", systemImage: listed ? "eye.slash.fill" : "eye.fill",
                action: { Task { await controller.setListed(.init(video: video, listed: !listed)) } })))
            entries.append(.divider)
        }
        entries.append(.item(.init(title: "Stop sharing…", systemImage: "xmark.circle", isDestructive: true,
            action: { stopping = video })))
        return entries
    }

    private func detail(_ video: HostedLibraryVideo) -> String {
        if video.status == "failed", let error = video.error { return error }
        if video.status == "uploading" { return "Upload incomplete · Resume from the recording’s Share panel" }
        var parts = [video.statusLabel]
        if let duration = video.duration, duration.isFinite, duration > 0 {
            parts.append(ProjectLibraryMetadata.durationLabel(duration))
        }
        if video.isOwnStorage { parts.append("Your Cloudflare") }
        if let width = video.width, let height = video.height { parts.append("\(width) × \(height)") }
        return parts.joined(separator: " · ")
    }

    private func empty(_ content: BlitzEmptyState.Configuration) -> some View {
        BlitzEmptyState(configuration: content).disabled(isSyncing)
    }
}
