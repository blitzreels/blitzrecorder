import AppKit
import SwiftUI

struct HostedSharingShowcaseItem: Identifiable {
    let id: UUID
    let title: String
    let duration: String?
    let image: NSImage
}

/// Signed-out Shared page: the user's own recordings, staged as the link they're about to send.
struct HostedSharingWelcome: View {
    @Bindable var controller: HostedVideoShareController
    let showcase: [HostedSharingShowcaseItem]
    @State private var appeared = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Metrics {
        static let card = CGSize(width: 336, height: 189)
        static let stageHeight: CGFloat = 248
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    stage
                        .padding(.bottom, 40)
                    copy
                        .padding(.bottom, 26)
                        .modifier(Reveal(isVisible: appeared, delay: 0.02))
                    HostedSignInForm(controller: controller, layout: .centered)
                        .frame(width: HostedSignInForm.width)
                        .modifier(Reveal(isVisible: appeared, delay: 0.03))
                    if let plan = controller.plan, plan.offersSharing {
                        plans(plan)
                            .padding(.top, 30)
                            .modifier(Reveal(isVisible: appeared, delay: 0.04))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: appeared)
        .animation(reduceMotion ? nil : .spring(duration: 0.15, bounce: 0), value: copied)
        .transaction { $0.disablesAnimations = false }
        .onAppear(perform: play)
    }

    private func play() {
        guard !appeared else { return }
        appeared = true
        guard !reduceMotion else { copied = true; return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            copied = true
        }
    }

    // MARK: Stage

    private var stage: some View {
        ZStack {
            ambient
                .opacity(appeared ? 1 : 0)
            ForEach(1...2, id: \.self) { depth in
                let level = CGFloat(depth)
                RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius)
                            .strokeBorder(BlitzUI.panelStroke, lineWidth: 1)
                    }
                    .frame(width: Metrics.card.width, height: Metrics.card.height)
                    .scaleEffect(1 - 0.06 * level)
                    .offset(y: appeared ? -11 * level : 0)
                    .opacity(appeared ? 1 - 0.35 * level : 0)
                    .zIndex(-level)
            }
            front
                .offset(y: appeared ? 0 : 6)
                .scaleEffect(appeared ? 1 : 0.98)
                .opacity(appeared ? 1 : 0)
            linkPill
                .offset(y: Metrics.card.height / 2 + 4)
                .offset(y: appeared ? 0 : 10)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .smooth(duration: 0.14).delay(0.03), value: appeared)
        }
        .frame(height: Metrics.stageHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of a shared recording link")
    }

    @ViewBuilder private var ambient: some View {
        if let image = showcase.first?.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 380, height: 190)
                .clipped()
                .blur(radius: 64)
                .saturation(1.5)
                .opacity(0.6)
                .offset(y: 16)
                .allowsHitTesting(false)
        } else {
            Ellipse()
                .fill(BlitzUI.accent.opacity(0.13))
                .frame(width: 420, height: 150)
                .blur(radius: 70)
        }
    }

    @ViewBuilder private var front: some View {
        if let item = showcase.first {
            frame(item, size: Metrics.card)
        } else {
            placeholderCard
        }
    }

    private func frame(_ item: HostedSharingShowcaseItem, size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                playButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(BlitzType.strong)
                        .foregroundStyle(BlitzUI.onMediaText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let duration = item.duration {
                        Text(duration).font(BlitzType.numeric).foregroundStyle(BlitzUI.onMediaSecondaryText)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: BlitzUI.surfaceRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius)
                .strokeBorder(LinearGradient(colors: [BlitzUI.strongStroke, BlitzUI.separator],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: BlitzUI.deepShadow, radius: 16, y: 8)
    }

    private var placeholderCard: some View {
        ZStack {
            LinearGradient(colors: [BlitzUI.scenePreviewFill, BlitzUI.canvasBackground],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            playButton
        }
        .frame(width: Metrics.card.width, height: Metrics.card.height)
        .clipShape(.rect(cornerRadius: BlitzUI.surfaceRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BlitzUI.surfaceRadius)
                .strokeBorder(LinearGradient(colors: [BlitzUI.strongStroke, BlitzUI.separator],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: BlitzUI.deepShadow, radius: 16, y: 8)
    }

    private var playButton: some View {
        Image(systemName: "play.fill")
            .font(BlitzType.symbol(17))
            .foregroundStyle(BlitzUI.onMediaText)
            .offset(x: 1.5)
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: .circle)
            .overlay { Circle().strokeBorder(BlitzUI.onMediaStroke, lineWidth: 1) }
            .environment(\.colorScheme, .dark)
    }

    private var linkPill: some View {
        HStack(spacing: 8) {
            Image(systemName: BlitzSymbols.share)
                .font(BlitzType.symbol(11))
                .foregroundStyle(BlitzUI.secondaryText)
            (Text("blitzrecorder.com/s/").foregroundStyle(BlitzUI.secondaryText)
             + Text("k3f9x2").foregroundStyle(BlitzUI.primaryText))
                .font(BlitzType.label)
            ZStack {
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .font(BlitzType.captionEmphasis)
                        .foregroundStyle(BlitzUI.accent)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Image(systemName: BlitzSymbols.copyLink)
                        .font(BlitzType.symbol(11))
                        .foregroundStyle(BlitzUI.secondaryText)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(minWidth: 62, alignment: .trailing)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 34)
        .background(.regularMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(BlitzUI.panelStroke, lineWidth: 1) }
        .shadow(color: BlitzUI.elevationShadow, radius: 10, y: 4)
    }

    // MARK: Copy

    private var copy: some View {
        VStack(spacing: 8) {
            Text("Send a recording as a link")
                .font(BlitzType.largeTitle)
                .foregroundStyle(BlitzUI.primaryText)
            Text("Viewers press play in any browser. No download, no account.")
                .font(BlitzType.callout)
                .foregroundStyle(BlitzUI.secondaryText)
        }
        .multilineTextAlignment(.center)
    }

    private func plans(_ plan: HostingPlan) -> some View {
        Text(pricing(plan))
            .font(BlitzType.caption)
            .foregroundStyle(BlitzUI.secondaryText)
            .multilineTextAlignment(.center)
            .help(plan.available ? "\(plan.allowance). Nothing to set up." : "")
    }

    private func pricing(_ plan: HostingPlan) -> String {
        switch (plan.available, plan.ownStorage == true) {
        case (true, true): "Hosting is \(plan.price) a month, or free with your own Cloudflare account."
        case (true, false): "Hosting is \(plan.price) a month."
        case (false, _): "Free with your own Cloudflare account."
        }
    }
}

private struct Reveal: ViewModifier {
    let isVisible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 4)
            .animation(reduceMotion ? nil : .smooth(duration: 0.14).delay(delay), value: isVisible)
    }
}
