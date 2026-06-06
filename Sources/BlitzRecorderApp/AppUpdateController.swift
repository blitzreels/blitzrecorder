import AppKit

#if DIRECT_DISTRIBUTION
import Sparkle
#endif

@MainActor
final class AppUpdateController: NSObject {
    static let releaseNotesURL = URL(string: "https://github.com/blitzreels/blitzrecorder-public/releases/latest")!

#if DIRECT_DISTRIBUTION
    private var updaterController: SPUStandardUpdaterController?
#endif

    override init() {
        super.init()
        startAutomaticUpdatesIfConfigured()
    }

    @objc func checkForUpdates(_ sender: Any?) {
#if DIRECT_DISTRIBUTION
        if let updaterController {
            updaterController.checkForUpdates(sender)
            return
        }

        openDirectReleasePage()
#else
        openAppStoreUpdatesPage()
#endif
    }

    @objc func openReleaseNotes(_ sender: Any?) {
        NSWorkspace.shared.open(Self.releaseNotesURL)
    }

    private func startAutomaticUpdatesIfConfigured() {
#if DIRECT_DISTRIBUTION
        guard Self.hasSparkleConfiguration else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        controller.startUpdater()
#endif
    }

#if DIRECT_DISTRIBUTION
    private static var hasSparkleConfiguration: Bool {
        guard let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedURLString),
              feedURL.scheme == "https",
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    private func openDirectReleasePage() {
        NSWorkspace.shared.open(Self.releaseNotesURL)
    }
#else
    private func openAppStoreUpdatesPage() {
        let updatesURL = URL(string: "macappstore://showUpdatesPage")
        let fallbackURL = URL(string: "https://apps.apple.com/account/subscriptions")
        if let url = updatesURL ?? fallbackURL {
            NSWorkspace.shared.open(url)
        }
    }
#endif
}
