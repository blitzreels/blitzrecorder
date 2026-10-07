import AppKit
import SwiftUI

struct FamilyApp: Identifiable {
    let name: String
    let detail: String
    let url: URL
    let actionTitle: String
    let iconResource: String

    var id: String { name }

    /// Other products by BlitzReels, linked from Settings > About and the Help menu.
    static let all: [FamilyApp] = [
        FamilyApp(
            name: "BlitzClean",
            detail: "Free, open-source menu bar monitor and cleaner for Mac.",
            url: URL(string: "https://github.com/blitzreels/blitzclean")!,
            actionTitle: "View on GitHub",
            iconResource: "BlitzCleanAppIcon"
        ),
        FamilyApp(
            name: "BlitzReels",
            detail: "Turns long videos into short clips with captions and reframing.",
            url: URL(string: "https://blitzreels.com")!,
            actionTitle: "Visit Website",
            iconResource: "BlitzReelsAppIcon"
        )
    ]

    var icon: NSImage? {
        Bundle.main.url(forResource: iconResource, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
}

/// Menu target for the Help menu's links to other BlitzReels products.
@MainActor
final class FamilyAppLinks: NSObject {
    static let shared = FamilyAppLinks()

    @objc func open(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }
}

struct FamilyAppsSection: View {
    private var wordmark: NSImage? {
        Bundle.main.url(forResource: "BlitzReelsWordmarkWhite", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Our other apps")
                    .font(BlitzType.section)
                    .foregroundStyle(BlitzUI.primaryText)
                Spacer()
                if let wordmark {
                    Image(nsImage: wordmark)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 13)
                        .accessibilityLabel("BlitzReels")
                }
            }
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(FamilyApp.all) { app in
                    HStack(spacing: 12) {
                        Group {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous).fill(BlitzUI.controlFill)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: BlitzUI.controlRadius, style: .continuous))
                        .accessibilityHidden(true)
                        SettingsRowLabel(.init(title: app.name, detail: app.detail))
                        Link(app.actionTitle, destination: app.url)
                            .blitzButton(.secondary)
                    }
                    .settingsRow()
                    if app.id != FamilyApp.all.last?.id {
                        SettingsRowDivider()
                    }
                }
            }
            .settingsCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
