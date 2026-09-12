import SwiftUI

struct AppUpdateToolbarButton: View {
    @EnvironmentObject private var updates: AppUpdateController

    var body: some View {
        if let version = updates.updateVersion {
            Button {
                updates.checkForUpdates(nil)
            } label: {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(BlitzUI.mint)
                }
            }
            .blitzButton(.secondary)
            .controlSize(.large)
            .fixedSize()
            .disabled(!updates.canCheckForUpdates)
            .accessibilityValue("Version \(version)")
            .help(updates.detail)
        }
    }

    private var title: String {
        switch updates.status {
        case .downloading: "Downloading…"
        case .readyToInstall: updates.actionTitle
        default: "New version"
        }
    }
}

struct AppUpdateBanner: View {
    @EnvironmentObject private var updates: AppUpdateController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(BlitzUI.mint)
            Text(updates.detail)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(updates.actionTitle) {
                updates.checkForUpdates(nil)
            }
            .blitzButton(.accent)
            .controlSize(.small)
            .disabled(!updates.canCheckForUpdates)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(BlitzUI.projectLibraryBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BlitzUI.separator).frame(height: 1)
        }
    }
}
