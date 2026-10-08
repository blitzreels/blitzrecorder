import AppKit
import SwiftUI

struct HostedVideoLibraryView: View {
    @Bindable var controller: HostedVideoShareController
    let showRecordings: () -> Void
    let thumbnail: (HostedLibraryVideo) -> NSImage?
    @State private var search = ""
    @State private var showsAccount = false

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
            header
            if controller.hasCheckedAccount && !controller.isConnected {
                HostedVideoSharePanel(controller: controller, context: .account, preparation: nil,
                    newExport: {}, close: {}, showLibrary: {})
                    .frame(maxWidth: 420, maxHeight: 520)
                    .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 24)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared videos").font(BlitzType.largeTitle)
                Text("Your watch links, together in one place.")
                    .font(BlitzType.callout).foregroundStyle(BlitzUI.supportingText)
            }
            Spacer()
            if controller.isConnected {
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
                    Label(controller.account?.email ?? "Account", systemImage: "person.crop.circle.fill")
                        .lineLimit(1)
                }
                .blitzButton(.secondary)
                .accessibilityLabel("Account")
                .popover(isPresented: $showsAccount, arrowEdge: .bottom) {
                    HostedVideoSharePanel(controller: controller, context: .account, preparation: nil,
                        newExport: {}, close: {}, showLibrary: {})
                        .frame(width: 320, height: 300)
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
                placeholderRows
            } else if controller.videos.isEmpty && controller.libraryMessage == nil {
                empty(.init(symbol: "link", title: "Your next video belongs here",
                    detail: "Open a recording, then choose Share to create its watch page.",
                    action: .init(title: "Choose a recording", run: showRecordings)))
            } else if controller.videos.isEmpty {
                empty(.init(symbol: "wifi.exclamationmark", title: "Shared videos unavailable",
                    detail: "Refresh when your connection is back.", action: nil))
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
        } else if let message = controller.libraryMessage ?? controller.accountMessage {
            noticeRow(.init(symbol: "exclamationmark.triangle", text: message,
                action: .init(title: "Retry", run: { Task { await controller.refreshVideos() } })))
        } else if !controller.isSubscribed, controller.isConnected {
            noticeRow(.init(symbol: "exclamationmark.triangle",
                text: "Your hosting plan is inactive. Enable it to make your watch links available again.",
                action: .init(title: "Manage hosting", run: { showsAccount = true })))
        }
    }

    private struct Notice {
        let symbol: String
        let text: String
        let action: Empty.Action
    }

    private func noticeRow(_ notice: Notice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: notice.symbol).foregroundStyle(BlitzUI.warning)
            Text(notice.text).font(BlitzType.body).foregroundStyle(BlitzUI.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(notice.action.title, action: notice.action.run)
                .blitzButton(.secondary).controlSize(.small)
                .disabled(isSyncing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(BlitzUI.warning.opacity(0.10), in: .rect(cornerRadius: BlitzControlMetrics.radius))
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

    private var placeholderRows: some View {
        LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 20) {
            ForEach(0..<6, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: BlitzUI.cardRadius).fill(BlitzUI.controlFill)
                        .aspectRatio(16 / 9, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 3).fill(BlitzUI.controlFill)
                        .frame(width: [180, 140, 200, 160, 120, 190][index], height: 11)
                    RoundedRectangle(cornerRadius: 3).fill(BlitzUI.quietFill).frame(width: 110, height: 9)
                }
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading shared videos")
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func card(_ video: HostedLibraryVideo) -> some View {
        let url = controller.watchURL(video)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: BlitzUI.cardRadius).fill(BlitzUI.controlFill)
                if let image = thumbnail(video) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(BlitzType.glyph(28))
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                if video.isProcessing {
                    Color.black.opacity(0.45)
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(video.statusLabel).font(BlitzType.captionEmphasis)
                    }
                } else if video.status == "failed" {
                    Color.black.opacity(0.45)
                    Label(video.statusLabel, systemImage: "exclamationmark.triangle.fill")
                        .font(BlitzType.captionEmphasis).foregroundStyle(BlitzUI.warning)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.duration, duration.isFinite, duration > 0 {
                    Text(SilenceTime.label(duration))
                        .font(BlitzType.captionEmphasis.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.65), in: .rect(cornerRadius: 5))
                        .padding(8)
                }
            }
            .contentShape(.rect(cornerRadius: BlitzUI.cardRadius))
            .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
            .pointingHandCursor(enabled: url != nil)
            .help(url == nil ? video.statusLabel : "Open the watch page")

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(BlitzType.strong).lineLimit(2).help(video.title)
                Text(detail(video))
                    .font(BlitzType.caption.monospacedDigit())
                    .foregroundStyle(video.status == "failed" ? BlitzUI.warning : BlitzUI.secondaryText)
                    .lineLimit(1)
                    .help(video.error ?? "")
            }
            HStack(spacing: 8) {
                if let url {
                    BlitzCopyButton(configuration: .watchLink(.init(url: url, title: "Copy link", emphasis: .secondary, width: .fixed(84))))
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Open", systemImage: "safari.fill")
                    }
                    .blitzButton(.secondary)
                    .help("Open the watch page in your browser")
                }
            }
            .controlSize(.small)
            .disabled(!controller.isSubscribed)
            .frame(height: BlitzControlMetrics.height(.small), alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(video.title)
    }

    private func detail(_ video: HostedLibraryVideo) -> String {
        if video.status == "failed", let error = video.error { return error }
        if video.status == "uploading" { return "Upload incomplete · Resume from the recording’s Share panel" }
        var parts = [video.statusLabel]
        if let width = video.width, let height = video.height { parts.append("\(width) × \(height)") }
        return parts.joined(separator: " · ")
    }

    private struct Empty {
        struct Action {
            let title: String
            let run: () -> Void
        }
        let symbol: String
        let title: String
        let detail: String
        let action: Action?
    }

    private func empty(_ content: Empty) -> some View {
        VStack(spacing: 10) {
            Image(systemName: content.symbol).font(BlitzType.glyph(28))
                .foregroundStyle(BlitzUI.secondaryText)
            Text(content.title).font(BlitzType.title)
            Text(content.detail).font(BlitzType.callout).foregroundStyle(BlitzUI.supportingText)
                .multilineTextAlignment(.center)
            if let action = content.action {
                Button(action.title, action: action.run)
                    .blitzButton(.accent).controlSize(.large).padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
