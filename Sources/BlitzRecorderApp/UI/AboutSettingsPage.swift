import AppKit
import SwiftUI

struct AboutSettingsPage: View {
    @EnvironmentObject private var updates: AppUpdateController
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsPageHeader(.init(
                    title: "About",
                    detail: "BlitzRecorder for Mac",
                    status: nil
                ))

                HStack(alignment: .center, spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BlitzRecorder")
                            .font(BlitzType.largeTitle)
                        Text(version)
                            .font(BlitzType.body)
                            .foregroundStyle(BlitzUI.secondaryText)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Free. All features included.", systemImage: "checkmark.circle.fill")
                        .font(BlitzType.headline)
                        .foregroundStyle(BlitzUI.mint)
                    Text("Unlimited recording and exports, iPhone camera, 4K, and 60 fps.")
                    Text("No account, payment, or license key needed.")
                        .foregroundStyle(BlitzUI.secondaryText)
                }
                .font(BlitzType.body)
                .fixedSize(horizontal: false, vertical: true)
                .settingsRow()

                VStack(spacing: 0) {
                    HStack {
                        SettingsRowLabel(.init(title: "App updates", detail: updates.detail))
                        Button(updates.actionTitle) {
                            updates.checkForUpdates(nil)
                        }
                        .blitzButton(.secondary)
                        .disabled(!updates.canCheckForUpdates)
                    }
                    .settingsRow()
                    if updates.isConfigured {
                        SettingsRowDivider()
                        Toggle("Check for updates automatically", isOn: Binding(
                            get: { updates.automaticChecksEnabled },
                            set: { updates.setAutomaticChecksEnabled($0) }
                        ))
                        .toggleStyle(.blitzSwitch)
                        .settingsRow()
                    }
                    SettingsRowDivider()
                    HStack {
                        SettingsRowLabel(.init(title: "What’s new", detail: "See the latest changes and releases."))
                        Link("Release Notes", destination: AppUpdateController.releaseNotesURL)
                            .blitzButton(.secondary)
                    }
                    .settingsRow()
                    SettingsRowDivider()
                    HStack {
                        SettingsRowLabel(.init(title: "Help", detail: "Get help with recording and editing."))
                        Link("Support", destination: AppLinks.support)
                            .blitzButton(.secondary)
                    }
                    .settingsRow()
                    SettingsRowDivider()
                    HStack {
                        SettingsRowLabel(.init(title: "Open source", detail: "Available under the AGPLv3 license."))
                        Link("Source Code", destination: URL(string: "https://github.com/blitzreels/blitzrecorder")!)
                            .blitzButton(.secondary)
                    }
                    .settingsRow()
                }
                .settingsSection(.init(title: "Resources", detail: nil, systemImage: "book.closed"))

                FamilyAppsSection()

                HStack(spacing: 18) {
                    Link("Website", destination: AppLinks.landingPage)
                    Link("Privacy", destination: AppLinks.privacy)
                    Link("Terms", destination: AppLinks.terms)
                }
                .font(BlitzType.body)
                .foregroundStyle(BlitzUI.secondaryText)
            }
            .settingsPageContent()
        }
        .background(BlitzUI.projectLibraryBackground)
    }
}
