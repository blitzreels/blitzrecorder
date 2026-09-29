import AppKit
import SwiftUI

struct AccountsSettingsPage: View {
    @Bindable var vm: RecorderViewModel
    @Bindable private var hosting = HostedVideoShareController.shared
    @Bindable private var reels = BlitzReelsHandoffController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "Accounts",
                    detail: "Sign in to share watch links and send recordings to BlitzReels.",
                    status: nil
                ))
                .padding(.bottom, 4)

                blitzRecorderSection
                blitzReelsSection
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
        .foregroundStyle(BlitzUI.primaryText)
        .task {
            await hosting.refresh()
            await reels.restoreConnection()
        }
    }

    private var blitzRecorderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("BlitzRecorder").font(BlitzType.section)
                    Text("Watch links and video hosting").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                }
            }
            VStack(spacing: 0) {
                if !hosting.hasCheckedAccount {
                    placeholderRow
                } else if hosting.isConnected {
                    HStack(spacing: 12) {
                        BlitzAccountAvatar(configuration: .init(
                            name: hosting.account?.email ?? "BlitzRecorder", imageURL: nil, size: 34
                        ))
                        SettingsRowLabel(.init(
                            title: hosting.account?.email ?? "BlitzRecorder account",
                            detail: hosting.isSubscribed ? "Hosting active" : "Free account · Local recording stays free"
                        ))
                        Spacer(minLength: 16)
                        Button { Task { await hosting.openBilling() } } label: {
                            Label(hosting.isSubscribed ? "Manage plan" : "Enable sharing",
                                  systemImage: hosting.isSubscribed ? "creditcard.fill" : "sparkles")
                        }
                        .blitzButton(hosting.isSubscribed ? .secondary : .accent)
                        .disabled(hosting.isPerformingAccountAction)
                    }
                    .settingsRow()
                    SettingsRowDivider()
                    HStack(spacing: 16) {
                        SettingsRowLabel(.init(
                            title: "Shared videos",
                            detail: hosting.videos.count == 1 ? "1 watch link" : "\(hosting.videos.count) watch links"
                        ))
                        Spacer(minLength: 16)
                        Button {
                            vm.projectLibraryNavigation.section = .shared
                            vm.showProjects()
                        } label: { Label("Open", systemImage: "film.stack.fill") }
                        .blitzButton(.secondary)
                    }
                    .settingsRow()
                    SettingsRowDivider()
                    HStack(spacing: 16) {
                        SettingsRowLabel(.init(
                            title: "Sign out",
                            detail: "Your recordings stay on this Mac. Watch links keep working."
                        ))
                        Spacer(minLength: 16)
                        Button { Task { await hosting.disconnect() } } label: {
                            Label(hosting.accountOperation == .signingOut ? "Signing out…" : "Sign out",
                                  systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .blitzButton(.secondary)
                        .disabled(hosting.isPerformingAccountAction || hosting.isRunning)
                    }
                    .settingsRow()
                    SettingsRowDivider()
                    HStack(spacing: 16) {
                        SettingsRowLabel(.init(
                            title: "Sign out everywhere",
                            detail: "Also signs out other Macs and any browser using this account."
                        ))
                        Spacer(minLength: 16)
                        Button { Task { await hosting.disconnect(everywhere: true) } } label: {
                            Text(hosting.accountOperation == .signingOutEverywhere ? "Signing out…" : "Sign out everywhere")
                        }
                        .blitzButton(.secondary)
                        .disabled(hosting.isPerformingAccountAction || hosting.isRunning)
                    }
                    .settingsRow()
                } else {
                    HostedVideoSharePanel(controller: hosting, context: .account, preparation: nil,
                                          newExport: {}, close: {}, showLibrary: {})
                        .frame(height: 200)
                        .padding(.horizontal, -16)
                        .clipShape(.rect(cornerRadius: BlitzUI.cardRadius))
                }
                if let message = hosting.accountMessage {
                    SettingsRowDivider()
                    Text(message).font(BlitzType.caption).foregroundStyle(BlitzUI.warning).settingsRow()
                }
            }
            .settingsCard()
        }
    }

    private var blitzReelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                BlitzReelsBrand().frame(width: 104, height: 18)
                Text("Captions and B-roll").font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
            }
            VStack(spacing: 0) {
                if let account = reels.connection.account {
                    HStack(spacing: 12) {
                        BlitzAccountAvatar(configuration: .init(
                            name: account.user.display_name ?? account.user.email,
                            imageURL: account.user.avatar_url.flatMap(URL.init(string:)),
                            size: 34
                        ))
                        SettingsRowLabel(.init(
                            title: account.user.display_name ?? account.user.email,
                            detail: account.user.display_name == nil ? "Connected" : "\(account.user.email) · Connected"
                        ))
                        Spacer(minLength: 16)
                        Button {
                            NSWorkspace.shared.open(reels.connection.client.origin.appendingPathComponent("dashboard/settings"))
                        } label: {
                            Label("Manage", systemImage: "arrow.up.right.square.fill")
                        }
                        .blitzButton(.secondary)
                        .help("Open your BlitzReels settings in the browser")
                    }
                    .settingsRow()
                    SettingsRowDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upload to").font(BlitzType.captionEmphasis).foregroundStyle(BlitzUI.secondaryText)
                        if account.workspaces.isEmpty {
                            Text("Create or join a workspace in BlitzReels to send recordings.")
                                .font(BlitzType.body).foregroundStyle(BlitzUI.secondaryText)
                        }
                        VStack(spacing: 2) {
                            ForEach(account.workspaces) { workspace in
                                workspaceRow(.init(workspace: workspace,
                                                   isSelected: reels.connection.selectedWorkspaceID == workspace.id))
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    SettingsRowDivider()
                    HStack(spacing: 16) {
                        SettingsRowLabel(.init(
                            title: "Disconnect",
                            detail: "Stop sending recordings to BlitzReels from this Mac."
                        ))
                        Spacer(minLength: 16)
                        Button(action: reels.disconnect) {
                            Label("Disconnect", systemImage: "xmark.circle.fill")
                        }
                        .blitzButton(.secondary)
                        .disabled(reels.isWorking)
                    }
                    .settingsRow()
                } else {
                    HStack(spacing: 16) {
                        SettingsRowLabel(.init(
                            title: reels.connection.hasCredential ? "Reconnect BlitzReels" : "Connect BlitzReels",
                            detail: "Send an exported MP4 to BlitzReels to add captions and B-roll."
                        ))
                        Spacer(minLength: 16)
                        Button(action: reels.connect) {
                            HStack(spacing: 6) {
                                if reels.isWorking { ProgressView().controlSize(.small) }
                                else { Image(systemName: "link") }
                                Text(reels.connection.hasCredential ? "Reconnect" : "Connect")
                            }
                        }
                        .blitzButton(.accent)
                        .disabled(reels.isWorking)
                    }
                    .settingsRow()
                }
                if !reels.status.isEmpty {
                    SettingsRowDivider()
                    Text(reels.status).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText).settingsRow()
                }
            }
            .settingsCard()
        }
    }

    private struct WorkspaceRowRequest {
        let workspace: BlitzReelsWorkspace
        let isSelected: Bool
    }

    private func workspaceRow(_ request: WorkspaceRowRequest) -> some View {
        let workspace = request.workspace
        let detail = [workspace.plan.map { $0.prefix(1).uppercased() + $0.dropFirst() }, workspace.role?.capitalized]
            .compactMap { $0 }.joined(separator: " · ")
        return Button { reels.selectWorkspace(workspace.id) } label: {
            HStack(spacing: 10) {
                BlitzRemoteIcon(configuration: .init(
                    name: workspace.name, seed: workspace.id,
                    imageURL: workspace.icon_url.flatMap(URL.init(string:)), size: 28, isCircle: false
                ))
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace.name).font(BlitzType.label).foregroundStyle(BlitzUI.primaryText)
                    if !detail.isEmpty {
                        Text(detail).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: request.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(BlitzType.glyph(15))
                    .foregroundStyle(request.isSelected ? BlitzUI.mint : BlitzUI.secondaryText)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzSelectionButtonStyle(isSelected: request.isSelected))
        .disabled(reels.isWorking)
        .accessibilityAddTraits(request.isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(workspace.name) workspace")
    }

    private var placeholderRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(BlitzUI.controlFill).frame(width: 180, height: 11)
                RoundedRectangle(cornerRadius: 3).fill(BlitzUI.quietFill).frame(width: 120, height: 9)
            }
            Spacer()
            RoundedRectangle(cornerRadius: BlitzControlMetrics.radius).fill(BlitzUI.quietFill)
                .frame(width: 110, height: BlitzControlMetrics.height(.regular))
        }
        .settingsRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your BlitzRecorder account")
    }
}

struct BlitzMonogram: View {
    struct Configuration {
        let text: String
        let seed: String
        let size: CGFloat
        let isCircle: Bool
    }

    let configuration: Configuration

    private static let palette: [Color] = [
        Color(hue: 0.44, saturation: 0.55, brightness: 0.62), Color(hue: 0.58, saturation: 0.5, brightness: 0.68),
        Color(hue: 0.72, saturation: 0.42, brightness: 0.68), Color(hue: 0.92, saturation: 0.45, brightness: 0.68),
        Color(hue: 0.06, saturation: 0.55, brightness: 0.72), Color(hue: 0.13, saturation: 0.55, brightness: 0.70),
    ]

    private var initials: String {
        let words = configuration.text.split(whereSeparator: { $0 == " " || $0 == "@" || $0 == "." }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private var color: Color {
        let hash = configuration.seed.unicodeScalars.reduce(UInt32(5_381)) { ($0 &* 33) &+ $1.value }
        return Self.palette[Int(hash % UInt32(Self.palette.count))]
    }

    var body: some View {
        Text(initials)
            .font(BlitzType.monogram(configuration.size * 0.38))
            .foregroundStyle(.white)
            .frame(width: configuration.size, height: configuration.size)
            .background(color, in: configuration.isCircle
                        ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: configuration.size * 0.26)))
            .accessibilityHidden(true)
    }
}

struct BlitzAccountAvatar: View {
    struct Configuration {
        let name: String
        let imageURL: URL?
        let size: CGFloat
    }

    let configuration: Configuration

    var body: some View {
        BlitzRemoteIcon(configuration: .init(
            name: configuration.name, seed: configuration.name,
            imageURL: configuration.imageURL, size: configuration.size, isCircle: true
        ))
    }
}

struct BlitzRemoteIcon: View {
    struct Configuration {
        let name: String
        let seed: String
        let imageURL: URL?
        let size: CGFloat
        let isCircle: Bool
    }

    let configuration: Configuration

    var body: some View {
        let monogram = BlitzMonogram(configuration: .init(
            text: configuration.name, seed: configuration.seed, size: configuration.size, isCircle: configuration.isCircle
        ))
        Group {
            if let url = configuration.imageURL {
                AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.15))) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: configuration.size, height: configuration.size)
        .clipShape(configuration.isCircle
                   ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: configuration.size * 0.26)))
        .accessibilityHidden(true)
    }
}
