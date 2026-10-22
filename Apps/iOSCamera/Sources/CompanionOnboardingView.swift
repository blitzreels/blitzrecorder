import BlitzRecorderCore
import BlitzRecorderDesign
import SwiftUI

/// Shown once, before pairing, for people who don't know the Mac app yet.
struct CompanionOnboardingView: View {
    let finish: () -> Void
    @State private var page = 0

    private static let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                CompanionOnboardingPage(
                    symbols: ["iphone", "arrow.right", "macbook"],
                    title: "Turn your iPhone into your Mac’s best camera.",
                    detail: "Film yourself in sharp, studio quality video while BlitzRecorder on your Mac runs the take."
                )
                .tag(0)
                CompanionOnboardingPage(
                    symbols: ["macbook"],
                    title: "Get BlitzRecorder on your Mac.",
                    detail: "It’s free. Your Mac starts each recording and keeps every file."
                ) {
                    ShareLink(item: BlitzRecorderProductIdentity.macInstallURL) {
                        Label("Send the link to my Mac", systemImage: BlitzSymbols.export)
                            .frame(maxWidth: .infinity)
                    }
                    .blitzButton(.secondary)
                    .controlSize(.large)
                }
                .tag(1)
                CompanionOnboardingPage(
                    symbols: ["hand.tap"],
                    title: "Pair with one tap.",
                    detail: "Open BlitzRecorder, choose this iPhone as the camera, then tap Connect here. "
                        + "Your Mac reconnects on its own after that."
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            VStack(spacing: 8) {
                Button(action: advance) {
                    Text(page == Self.lastPage ? "Start" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .blitzButton(.accent)
                .controlSize(.extraLarge)
                Button(page == 1 ? "I already have it" : "Skip", action: page == 1 ? advance : finish)
                    .blitzButton(.quiet)
                    .opacity(page == Self.lastPage ? 0 : 1)
                    .disabled(page == Self.lastPage)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(BlitzUI.canvasBackground.ignoresSafeArea())
        .animation(.easeOut(duration: 0.15), value: page)
    }

    private func advance() {
        if page < Self.lastPage {
            page += 1
        } else {
            finish()
        }
    }
}

private struct CompanionOnboardingPage<Accessory: View>: View {
    let symbols: [String]
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                ForEach(symbols, id: \.self) { symbol in
                    BlitzSymbol(configuration: .init(name: symbol, size: symbol == "arrow.right" ? 22 : 52))
                        .foregroundStyle(symbol == "arrow.right" ? BlitzUI.tertiaryText : BlitzUI.accent)
                }
            }
            .frame(height: 120)
            VStack(spacing: 12) {
                Text(title)
                    .font(BlitzType.largeTitle)
                    .foregroundStyle(BlitzUI.primaryText)
                Text(detail)
                    .font(BlitzType.callout)
                    .foregroundStyle(BlitzUI.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            accessory
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
    }
}

extension CompanionOnboardingPage where Accessory == EmptyView {
    init(symbols: [String], title: String, detail: String) {
        self.init(symbols: symbols, title: title, detail: detail) { EmptyView() }
    }
}

#Preview("Onboarding") {
    CompanionOnboardingView(finish: {})
        .preferredColorScheme(.dark)
}
