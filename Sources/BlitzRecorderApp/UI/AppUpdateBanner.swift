import SwiftUI

struct AppUpdateSidebarCard: View {
    @EnvironmentObject private var updates: AppUpdateController

    var body: some View {
        if let version = updates.updateVersion {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(BlitzType.symbol(15))
                        .foregroundStyle(BlitzUI.mint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(BlitzType.strong)
                            .foregroundStyle(BlitzUI.primaryText)
                        Text(subtitle(version))
                            .font(BlitzType.caption)
                            .foregroundStyle(updates.installationBlockedReason == nil ? BlitzUI.secondaryText : BlitzUI.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if case .downloading = updates.status {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(BlitzUI.mint)
                        .accessibilityLabel("Downloading update")
                } else {
                    HStack(spacing: 6) {
                        Button {
                            updates.checkForUpdates(nil)
                        } label: {
                            Text(buttonTitle).frame(maxWidth: .infinity)
                        }
                        .blitzButton(isReady ? .accent : .secondary)
                        .controlSize(.small)
                        .disabled(!updates.canCheckForUpdates)
                        Button {
                            updates.openReleaseNotes(nil)
                        } label: {
                            Image(systemName: "doc.text")
                                .frame(width: 16)
                        }
                        .blitzButton(.quiet)
                        .controlSize(.small)
                        .help("What’s new in \(version)")
                        .accessibilityLabel("Release notes")
                    }
                }
            }
            .padding(10)
            .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Update available")
            .accessibilityValue("Version \(version)")
            .help(updates.detail)
        }
    }

    private var isReady: Bool {
        if case .readyToInstall = updates.status { return true }
        return false
    }

    private var title: String {
        switch updates.status {
        case .downloading: "Downloading update"
        case .readyToInstall: "Update ready"
        default: "Update available"
        }
    }

    private func subtitle(_ version: String) -> String {
        updates.installationBlockedReason ?? "BlitzRecorder \(version)"
    }

    private var buttonTitle: String {
        isReady ? updates.actionTitle : "Update…"
    }
}

struct AppUpdateBadge: View {
    @EnvironmentObject private var updates: AppUpdateController

    var body: some View {
        if updates.updateVersion != nil {
            BlitzStatusDot(tone: .ready, diameter: 7)
                .overlay(Circle().stroke(BlitzUI.panelBackground, lineWidth: 2))
                .accessibilityLabel("Update available")
        }
    }
}
