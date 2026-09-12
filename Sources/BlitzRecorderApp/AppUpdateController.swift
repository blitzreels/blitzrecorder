import AppKit
import Combine

#if DIRECT_DISTRIBUTION
import Sparkle
#endif

@MainActor
protocol AppUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var onReadinessChange: (() -> Void)? { get set }
    func start() throws
    func checkForUpdates()
    func checkForUpdatesInBackground()
}

@MainActor
final class AppUpdateController: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading(String)
        case readyToInstall(String)
        case failed(String)
        case unavailable
    }

    struct Installation {
        let version: String
        let install: () -> Void
    }

    static let releaseNotesURL = URL(string: "https://github.com/blitzreels/blitzrecorder/releases/latest")!
    @Published private(set) var status: Status = .idle { didSet { onStateChange?() } }
    @Published private(set) var automaticChecksEnabled = false
    @Published private(set) var isConfigured = false
    @Published private(set) var hasPendingManualCheck = false { didSet { onStateChange?() } }
    @Published var installationBlockedReason: String? { didSet { onStateChange?() } }
    var onStateChange: (() -> Void)?
    private var driver: (any AppUpdateDriving)?
    private var hasStarted = false
    private var installHandler: (() -> Void)?

    override init() {
        super.init()
    }

    init(driver: any AppUpdateDriving) {
        self.driver = driver
        super.init()
    }

    nonisolated static func hasSparkleConfiguration(feedURLString: String?, publicKey: String?) -> Bool {
        guard let feedURLString,
              let feedURL = URL(string: feedURLString),
              feedURL.scheme == "https",
              let publicKey,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    var updateVersion: String? {
        switch status {
        case .available(let version), .downloading(let version), .readyToInstall(let version): version
        default: nil
        }
    }

    var actionTitle: String {
        if installHandler != nil { return "Restart and Update" }
        switch status {
        case .checking: return "Checking for Updates…"
        case .available: return "View Update…"
        case .downloading: return "View Update Progress…"
        case .readyToInstall: return "Install Update…"
        default: return "Check for Updates…"
        }
    }

    var detail: String {
        if updateVersion != nil, let installationBlockedReason { return installationBlockedReason }
        switch status {
        case .idle:
#if DIRECT_DISTRIBUTION
            return automaticChecksEnabled ? "Checks at startup and daily." : "Automatic checking is off."
#else
            return "Updates are managed by the App Store."
#endif
        case .checking: return "Looking for the latest version…"
        case .upToDate: return "You’re up to date."
        case .available(let version): return "BlitzRecorder \(version) is available."
        case .downloading(let version): return "Downloading BlitzRecorder \(version)…"
        case .readyToInstall(let version): return "BlitzRecorder \(version) is ready to install."
        case .failed(let message): return message
        case .unavailable: return "Updates are unavailable in this development build."
        }
    }

    var canCheckForUpdates: Bool {
        if updateVersion != nil, installationBlockedReason != nil { return false }
        return !hasPendingManualCheck
    }

    func start() {
        startIfNeeded(checkAtStartup: true)
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard let driver else { return }
        driver.automaticallyChecksForUpdates = enabled
        automaticChecksEnabled = driver.automaticallyChecksForUpdates
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard canCheckForUpdates else { return }
        if let installHandler {
            installHandler()
            return
        }
        startIfNeeded(checkAtStartup: false)
        guard driver != nil, hasStarted else {
#if DIRECT_DISTRIBUTION
            let alert = NSAlert()
            alert.messageText = "Updates are unavailable in this build"
            alert.informativeText = status == .unavailable
                ? "This development build has no signed update feed. Release builds check automatically when BlitzRecorder opens."
                : detail
            alert.addButton(withTitle: "View Releases")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { openReleaseNotes(nil) }
#else
            NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
#endif
            return
        }
        hasPendingManualCheck = true
        resumeManualCheckIfReady()
    }

    @objc func openReleaseNotes(_ sender: Any?) {
        NSWorkspace.shared.open(Self.releaseNotesURL)
    }

    func prepareInstallation(_ installation: Installation) {
        installHandler = installation.install
        hasPendingManualCheck = false
        status = .readyToInstall(installation.version)
    }

    func finishUpdateCycle(error: (any Error)?) {
        if let error {
            installHandler = nil
            status = .failed(error.localizedDescription)
        } else if status == .checking {
            status = .idle
        }
        resumeManualCheckIfReady()
    }

    private func startIfNeeded(checkAtStartup: Bool) {
        guard !hasStarted else { return }
#if DIRECT_DISTRIBUTION
        if driver == nil, Self.hasSparkleConfiguration(
            feedURLString: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        ) {
            driver = SparkleUpdateDriver(delegate: self)
        }
#endif
        guard let driver else {
#if DIRECT_DISTRIBUTION
            status = .unavailable
#endif
            return
        }
        driver.onReadinessChange = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            self.resumeManualCheckIfReady()
            self.onStateChange?()
        }
        do {
            try driver.start()
            hasStarted = true
            isConfigured = true
            automaticChecksEnabled = driver.automaticallyChecksForUpdates
            if checkAtStartup, automaticChecksEnabled {
                status = .checking
                driver.checkForUpdatesInBackground()
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func resumeManualCheckIfReady() {
        guard hasPendingManualCheck, let driver, driver.canCheckForUpdates else { return }
        hasPendingManualCheck = false
        if updateVersion == nil { status = .checking }
        driver.checkForUpdates()
    }
}

#if DIRECT_DISTRIBUTION
@MainActor
private final class SparkleUpdateDriver: AppUpdateDriving {
    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?
    var onReadinessChange: (() -> Void)?

    init(delegate: AppUpdateController) {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: delegate)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.onReadinessChange?() }
        }
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() throws { try controller.updater.start() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
    func checkForUpdatesInBackground() { controller.updater.checkForUpdatesInBackground() }
}

@MainActor
extension AppUpdateController: SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        status = .downloading(item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        status = .readyToInstall(item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        prepareInstallation(.init(version: item.displayVersionString, install: immediateInstallHandler))
        return true
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard installationBlockedReason != nil else { return false }
        prepareInstallation(.init(version: item.displayVersionString, install: installHandler))
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error = error as NSError?,
           error.domain == SUSparkleErrorDomain,
           error.code == SUError.noUpdateError.rawValue {
            status = .upToDate
            finishUpdateCycle(error: nil)
            return
        }
        finishUpdateCycle(error: error)
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        installationBlockedReason == nil && immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        status = state.stage == .notDownloaded ? .available(update.displayVersionString) : .readyToInstall(update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        guard installHandler == nil else { return }
        status = .idle
    }
}
#endif
