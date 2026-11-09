import AppKit
import SwiftUI

@MainActor
enum BlitzReelsPitch {
    struct Outcome: Identifiable {
        let symbol: String
        let title: String
        let detail: String

        var id: String { title }
    }

    struct Offer {
        let headline: String
        let outcomes: [Outcome]
    }

    static let tagline = "AI clipping and post scheduling"
    static let summary = "BlitzReels is an AI clipping and post scheduling service."
    static let shortFormLimit: Double = 5 * 60
    static let shortFormHeadline = "Looks like you're editing a short-form video"
    static let shortFormDetail = "\(summary) Add captions and B-roll to this video, then schedule it on YouTube Shorts, TikTok and LinkedIn."
    static let trialTerms = "Free for 7 days, no card needed. Scheduling is on the Growth and Agency plans."
    static let longVideoOffer = Offer(headline: "Turn this video into a week of posts", outcomes: [
        .init(symbol: "sparkles", title: "AI finds your best moments",
              detail: "Get short vertical clips from this one video."),
        .init(symbol: "captions.bubble", title: "Add captions and B-roll",
              detail: "Then fix any word or cut in the timeline."),
        .init(symbol: "calendar", title: "Schedule your week of posts",
              detail: "YouTube Shorts, TikTok and LinkedIn.")
    ])
    static let shortVideoOffer = Offer(headline: "Caption this video and schedule the post", outcomes: [
        .init(symbol: "captions.bubble", title: "Add captions and B-roll",
              detail: "Then fix any word or cut in the timeline."),
        .init(symbol: "calendar", title: "Schedule the post",
              detail: "YouTube Shorts, TikTok and LinkedIn."),
        .init(symbol: "sparkles", title: "Clip your longer videos",
              detail: "AI finds the best moments in videos over 5 minutes.")
    ])

    static let mark = bundledImage("BlitzReelsMark")

    static func isShortForm(_ timeline: EditorTimelineProjection) -> Bool {
        timeline.duration > 0 && timeline.duration <= shortFormLimit
    }

    static func offer(for timeline: EditorTimelineProjection) -> Offer {
        isShortForm(timeline) ? shortVideoOffer : longVideoOffer
    }

    static func bundledImage(_ name: String) -> Image? {
        Bundle.main.url(forResource: name, withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            .map(Image.init(nsImage:))
    }

    static var trialURL: URL {
        let origin = BlitzReelsHandoffController.shared.connection.client.origin
        var parts = URLComponents(url: origin.appendingPathComponent("register"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            .init(name: "utm_source", value: "blitzrecorder"),
            .init(name: "utm_medium", value: "app"),
            .init(name: "utm_campaign", value: "sidebar_card")
        ]
        return parts.url!
    }

    static var dashboardURL: URL {
        BlitzReelsHandoffController.shared.connection.client.origin.appendingPathComponent("dashboard")
    }
}

struct BlitzReelsOutcomeList: View {
    let outcomes: [BlitzReelsPitch.Outcome]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(outcomes) { outcome in
                HStack(alignment: .center, spacing: 10) {
                    BlitzIconTile(symbolName: outcome.symbol, isSelected: false, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outcome.title).font(BlitzType.strong).foregroundStyle(BlitzUI.primaryText)
                        Text(outcome.detail).font(BlitzType.caption).foregroundStyle(BlitzUI.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct AppSidebarBlitzReelsCard: View {
    @AppStorage("blitzReels.sidebarCardDismissed") private var isDismissed = false
    private let connection = BlitzReelsHandoffController.shared.connection

    private var isConnected: Bool { connection.account != nil }

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    BlitzReelsBrand().frame(width: 100, height: 15)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark").frame(width: 14, height: 14)
                    }
                    .blitzButton(.quiet)
                    .controlSize(.mini)
                    .help("Hide from the sidebar")
                    .accessibilityLabel("Hide BlitzReels from the sidebar")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit and post with AI")
                        .font(BlitzType.strong)
                        .foregroundStyle(BlitzUI.primaryText)
                    Text("Clips your recordings and schedules the posts.")
                        .font(BlitzType.caption)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    NSWorkspace.shared.open(isConnected ? BlitzReelsPitch.dashboardURL : BlitzReelsPitch.trialURL)
                } label: {
                    Text(isConnected ? "Open BlitzReels" : "Try free for 7 days").frame(maxWidth: .infinity)
                }
                .blitzButton(isConnected ? .secondary : .accent)
                .controlSize(.small)
            }
            .padding(10)
            .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("BlitzReels")
            .help(BlitzReelsPitch.summary)
        }
    }
}

struct EditorExportBlitzReelsOffer: View {
    let send: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                BlitzReelsBrand().frame(width: 94, height: 14)
                Text(BlitzReelsPitch.tagline)
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Send to BlitzReels", systemImage: "paperplane", action: send)
                .blitzButton(.accent)
                .controlSize(.small)
                .fixedSize()
        }
        .help(BlitzReelsPitch.summary)
    }
}

struct EditorOutputsBlitzReelsRow: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                BlitzReelsBrand().frame(width: 87, height: 13)
                Spacer(minLength: 4)
                Text("Clip and schedule")
                    .font(BlitzType.caption)
                    .foregroundStyle(BlitzUI.supportingText)
                Image(systemName: "chevron.right")
                    .font(BlitzType.symbol(10))
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .frame(minHeight: 24)
            .contentShape(.rect)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .help(BlitzReelsPitch.summary)
        .accessibilityLabel("BlitzReels: clip and schedule")
    }
}

struct EditorShortFormBlitzReelsNudge: View {
    struct Configuration {
        let open: () -> Void
        let dismiss: () -> Void
    }

    let configuration: Configuration

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BlitzAdaptiveRow(.init(minimumContentWidth: 260)) {
                VStack(alignment: .leading, spacing: 6) {
                    BlitzReelsBrand().frame(width: 134, height: 20)
                    Text(BlitzReelsPitch.shortFormHeadline)
                        .font(BlitzType.title)
                        .foregroundStyle(BlitzUI.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BlitzReelsPitch.shortFormDetail)
                        .font(BlitzType.body)
                        .foregroundStyle(BlitzUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Edit it with BlitzReels", action: configuration.open)
                    .blitzButton(.accent)
                    .fixedSize()
            }
            Button(action: configuration.dismiss) { Image(systemName: "xmark") }
                .blitzButton(.quiet)
                .help("Hide for this video")
                .accessibilityLabel("Hide BlitzReels suggestion for this video")
        }
        .editorNoticeSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("BlitzReels suggestion")
    }
}
