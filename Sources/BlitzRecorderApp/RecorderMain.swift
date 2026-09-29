import AppKit
import Darwin

let showMainWindowNotification = Notification.Name("dev.blitzreels.blitzrecorder.show-main-window")

private enum SingleInstanceGate {
    private static let fallbackBundleIdentifier = "dev.blitzreels.blitzrecorder"
    private static var lock: SingleInstanceLock?

    static func claimLaunch() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier
        guard let acquiredLock = SingleInstanceLock(bundleIdentifier: bundleIdentifier) else {
            activateExistingInstance(bundleIdentifier: bundleIdentifier)
            DistributedNotificationCenter.default().postNotificationName(
                showMainWindowNotification,
                object: nil,
                deliverImmediately: true
            )
            return false
        }

        lock = acquiredLock
        return true
    }

    private static func activateExistingInstance(bundleIdentifier: String) {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let existingApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }

        existingApp?.activate(options: [.activateAllWindows])
    }
}

private final class SingleInstanceLock {
    private let fileDescriptor: Int32

    init?(bundleIdentifier: String) {
        let lockURL = Self.lockURL(bundleIdentifier: bundleIdentifier)
        try? FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return nil
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return nil
        }

        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
    }

    private static func lockURL(bundleIdentifier: String) -> URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return supportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("BlitzRecorder.lock")
    }
}

@main
@MainActor
struct RecorderMain {
    private static var appDelegate: AppDelegate?

    static func main() {
        guard SingleInstanceGate.claimLaunch() else {
            exit(EXIT_SUCCESS)
        }

        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        delegate.launchIfNeeded()
        app.finishLaunching()
        app.run()
    }
}
