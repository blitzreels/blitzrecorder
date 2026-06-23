import AppKit
import Darwin
import SwiftUI

private let showMainWindowNotification = Notification.Name("dev.blitzreels.blitzrecorder.show-main-window")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MenuActionsTarget {
    private let accessController = AccessController()
    private lazy var coordinator = RecorderCoordinator(accessController: accessController)
    private var windowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private var blinkTimer: Timer?
    private var statusElapsedTimer: Timer?
    private var statusElapsedStartedAt: Date?
    private var statusElapsedAccumulated: TimeInterval = 0
    private var blinkOn = false
    private var mainMenuBuilder: MainMenuBuilder?
    private lazy var updateController = AppUpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchIfNeeded()
    }

    func launchIfNeeded() {
        guard windowController == nil else {
            presentMainWindow()
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowMainWindowNotification),
            name: showMainWindowNotification,
            object: nil
        )

        accessController.configure()
        NSApp.setActivationPolicy(.regular)
        applyDevIconBadgeIfNeeded()
        _ = updateController

        let windowController = MainWindowController(coordinator: coordinator)
        self.windowController = windowController

        coordinator.onStateChanged = { [weak self] state in
            self?.windowController?.update(for: state)
            self?.updateStatusItem(for: state)
            self?.rebuildMenu()
            self?.mainMenuBuilder?.rebuild()
        }
        coordinator.onMessage = { [weak self] message in
            self?.windowController?.setDetail(message)
            self?.rebuildMenu()
        }
        coordinator.onSavedRecording = { [weak self] output in
            self?.windowController?.applySavedRecordingOutput(output)
            self?.rebuildMenu()
        }
        coordinator.onPostRecordingProject = { [weak self] output in
            self?.windowController?.applyPostRecordingProjectOutput(output)
            self?.rebuildMenu()
        }
        coordinator.onRecordingRecovery = { [weak self] output in
            self?.windowController?.applyRecoveryOutput(output)
            self?.rebuildMenu()
        }
        coordinator.onRenderProgress = { [weak self] progress in
            self?.windowController?.updateRenderProgress(progress)
        }
        coordinator.onRuleOfThirdsOverlayChanged = { [weak self] visible in
            self?.windowController?.syncRuleOfThirdsOverlay()
            self?.rebuildMenu()
        }
        coordinator.onSocialSafeZoneOverlayChanged = { [weak self] _ in
            self?.windowController?.syncRuleOfThirdsOverlay()
            self?.rebuildMenu()
        }
        coordinator.onRequestForeground = { [weak self] in
            self?.presentMainWindow()
        }

        mainMenuBuilder = MainMenuBuilder(coordinator: coordinator, target: self)
        mainMenuBuilder?.install()
        mainMenuBuilder?.refreshDevices()

        buildStatusItem()
        updateStatusItem(for: coordinator.state)
        presentMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.presentMainWindow()
        }
        writeScreenshotIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.presentMainWindow()
        }
        return true
    }

    @objc private func handleShowMainWindowNotification(_ notification: Notification) {
        presentMainWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if windowController?.window?.isVisible != true {
            presentMainWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            accessController.handleBlitzRecorderURL(url)
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = appStatusImage()
        item.button?.imagePosition = .imageLeft
        item.button?.imageScaling = .scaleProportionallyDown
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show BlitzRecorder", action: #selector(showWindow), keyEquivalent: ""))
        menu.addItem(.separator())

        switch coordinator.state {
        case .idle:
            let readiness = coordinator.recordingReadiness()
            let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "r")
            startItem.isEnabled = readiness.isReady
            menu.addItem(startItem)

            if !readiness.isReady {
                menu.addItem(Self.wrappingCaptionItem(readiness.detail))
            }
        case .starting:
            let item = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        case .recording:
            menu.addItem(NSMenuItem(title: "Pause", action: #selector(pauseRecording), keyEquivalent: "p"))
            menu.addItem(NSMenuItem(title: "Stop", action: #selector(stopRecording), keyEquivalent: "s"))
            addSceneItems(to: menu)
        case .paused:
            menu.addItem(NSMenuItem(title: "Resume", action: #selector(resumeRecording), keyEquivalent: "p"))
            menu.addItem(NSMenuItem(title: "Stop", action: #selector(stopRecording), keyEquivalent: "s"))
            addSceneItems(to: menu)
        case .finishing:
            let item = NSMenuItem(title: "Finishing...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let fitWindowItem = NSMenuItem(title: "Fit Front Window for Shorts", action: #selector(fitFrontWindowForShorts), keyEquivalent: "")
        menu.addItem(fitWindowItem)
        menu.addItem(NSMenuItem(title: "Target Window Wider", action: #selector(makeTargetWindowWider), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Target Window Narrower", action: #selector(makeTargetWindowNarrower), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Target Window Taller", action: #selector(makeTargetWindowTaller), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Target Window Shorter", action: #selector(makeTargetWindowShorter), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: coordinator.settings.showsRuleOfThirdsOverlay ? "Hide Rule of Thirds" : "Show Rule of Thirds", action: #selector(toggleOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+"))
        menu.addItem(NSMenuItem(title: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-"))
        menu.addItem(NSMenuItem(title: "Reset Zoom", action: #selector(resetZoom), keyEquivalent: "0"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
    }

    private static func wrappingCaptionItem(_ text: String, width: CGFloat = 300) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = width
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width + 33),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 21),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7),
        ])
        item.view = container
        return item
    }

    private func addSceneItems(to menu: NSMenu) {
        let scenes = coordinator.scenesForCurrentLayout()
        guard !scenes.isEmpty else { return }

        menu.addItem(.separator())
        let heading = NSMenuItem(title: "Switch Scene", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let selectedID = coordinator.selectedSceneIDForCurrentLayout()
        for scene in scenes {
            let item = NSMenuItem(title: scene.name, action: #selector(chooseSceneItem), keyEquivalent: "")
            item.representedObject = scene.id
            item.state = scene.id == selectedID ? .on : .off
            menu.addItem(item)
        }

        if coordinator.settings.visibleSources.contains(.screen) {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Switch Window/App...", action: #selector(pickScreen), keyEquivalent: ""))
        }
    }

    private func updateStatusItem(for state: RecordingState) {
        blinkTimer?.invalidate()
        blinkTimer = nil

        switch state {
        case .idle:
            resetStatusElapsed()
            statusItem?.button?.image = appStatusImage()
            statusItem?.button?.title = ""
        case .starting:
            resetStatusElapsed()
            statusItem?.button?.image = statusImage(color: .systemBlue)
            statusItem?.button?.title = ""
        case .recording:
            resumeStatusElapsed()
            statusItem?.button?.image = statusImage(color: .systemRed)
        case .paused:
            pauseStatusElapsed()
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.blinkOn.toggle()
                    self.statusItem?.button?.image = self.statusImage(color: self.blinkOn ? .systemRed : .clear)
                }
            }
        case .finishing:
            stopStatusElapsedTimer()
            statusItem?.button?.image = statusImage(color: .systemOrange)
        }
    }

    private func resumeStatusElapsed() {
        if statusElapsedStartedAt == nil {
            statusElapsedStartedAt = Date()
        }
        statusElapsedTimer?.invalidate()
        statusElapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusElapsedTitle()
            }
        }
        updateStatusElapsedTitle()
    }

    private func pauseStatusElapsed() {
        if let statusElapsedStartedAt {
            statusElapsedAccumulated += Date().timeIntervalSince(statusElapsedStartedAt)
            self.statusElapsedStartedAt = nil
        }
        stopStatusElapsedTimer()
        updateStatusElapsedTitle()
    }

    private func resetStatusElapsed() {
        stopStatusElapsedTimer()
        statusElapsedStartedAt = nil
        statusElapsedAccumulated = 0
    }

    private func stopStatusElapsedTimer() {
        statusElapsedTimer?.invalidate()
        statusElapsedTimer = nil
    }

    private func updateStatusElapsedTitle() {
        let activeSeconds = statusElapsedStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let totalSeconds = Int((statusElapsedAccumulated + activeSeconds).rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        statusItem?.button?.title = " \(String(format: "%02d:%02d", minutes, seconds))"
    }

    private func statusImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 12, height: 12)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func appStatusImage() -> NSImage {
        let image = NSApp.applicationIconImage.copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func applyDevIconBadgeIfNeeded() {
#if DEBUG
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_HIDE_DEV_ICON"] != "1" else { return }
#else
        guard Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true else { return }
#endif
        guard let base = devIconBaseImage() else { return }

        let side: CGFloat = 512
        let canvas = NSSize(width: side, height: side)
        let badged = NSImage(size: canvas)
        badged.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: canvas))

        let badge = NSRect(x: side * 0.10, y: side * 0.07, width: side * 0.80, height: side * 0.22)
        let pill = NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2)
        NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.16, alpha: 1).setFill()
        pill.fill()

        let label = NSAttributedString(
            string: "DEV",
            attributes: [
                .font: NSFont.systemFont(ofSize: badge.height * 0.62, weight: .heavy),
                .foregroundColor: NSColor.black,
                .kern: 2
            ]
        )
        let labelSize = label.size()
        label.draw(at: NSPoint(x: badge.midX - labelSize.width / 2, y: badge.midY - labelSize.height / 2))
        badged.unlockFocus()

        NSApp.applicationIconImage = badged
    }

    private func devIconBaseImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

#if DEBUG
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appIconURL = repoRoot.appendingPathComponent("Resources/AppIcon.png")
        if let image = NSImage(contentsOf: appIconURL) {
            return image
        }
#endif

        return NSApp.applicationIconImage.copy() as? NSImage
    }

    @objc private func showWindow() {
        presentMainWindow()
    }

    @objc func showSettings() {
        windowController?.presentSettings()
    }

    @objc func showAbout() {
        AppSupportActions.showAboutPanel()
    }

    @objc func checkForUpdates() {
        updateController.checkForUpdates(nil)
    }

    @objc func openReleaseNotes() {
        updateController.openReleaseNotes(nil)
    }

    @objc func openHelp() {
        AppSupportActions.openHelp()
    }

    @objc func reportIssue() {
        AppSupportActions.reportIssue(diagnostics: diagnosticsReport())
    }

    @objc func sendFeedback() {
        AppSupportActions.sendFeedback(diagnostics: diagnosticsReport())
    }

    @objc func copyDiagnostics() {
        AppSupportActions.copyDiagnostics(diagnosticsReport())
    }

    @objc func openPrivacyPolicy() {
        AppSupportActions.openPrivacyPolicy()
    }

    private func diagnosticsReport() -> String {
        AppDiagnostics.report(coordinator: coordinator, accessController: accessController)
    }

    private func presentMainWindow() {
        guard let windowController, let window = windowController.window else { return }

        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)

        window.collectionBehavior = [.moveToActiveSpace]
        window.alphaValue = 1
        window.deminiaturize(nil)
        moveWindowIntoVisibleFrameIfNeeded(window)
        window.setIsVisible(true)

        window.level = .normal
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
        window.displayIfNeeded()

        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private func writeScreenshotIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BLITZRECORDER_SCREENSHOT_MODE"] == "1",
              let outputPath = environment["BLITZRECORDER_SCREENSHOT_OUTPUT"],
              !outputPath.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            do {
                let outputURL = try self.writeScreenshot(to: outputPath)
                print("BLITZRECORDER_SCREENSHOT_WRITTEN=\(outputURL.path)")
                NSApp.terminate(nil)
            } catch {
                fputs("BlitzRecorder screenshot failed: \(error)\n", stderr)
                NSApp.terminate(nil)
            }
        }
    }

    private func writeScreenshot(to outputPath: String) throws -> URL {
        let requestedURL = URL(fileURLWithPath: outputPath)
        do {
            try windowController?.writeScreenshot(to: requestedURL)
            return requestedURL
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(requestedURL.lastPathComponent)
            try windowController?.writeScreenshot(to: fallbackURL)
            return fallbackURL
        }
    }

    private func moveWindowIntoVisibleFrameIfNeeded(_ window: NSWindow) {
        guard let visibleFrame = NSScreen.main?.visibleFrame, visibleFrame.width > 0, visibleFrame.height > 0 else {
            return
        }

        if window.frame.intersects(visibleFrame) {
            return
        }

        let margin: CGFloat = 48
        let width = min(max(window.frame.width, 1180), max(visibleFrame.width - margin * 2, 980))
        let height = min(max(window.frame.height, 860), max(visibleFrame.height - margin * 2, 760))
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2

        window.setFrame(
            NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded()),
            display: true
        )
    }

    @objc func startRecording() {
        coordinator.start()
    }

    @objc func pauseRecording() {
        coordinator.pause()
    }

    @objc func resumeRecording() {
        coordinator.resume()
    }

    @objc func stopRecording() {
        coordinator.stop()
    }

    @objc private func toggleOverlay() {
        coordinator.setRuleOfThirdsOverlayVisible(!coordinator.settings.showsRuleOfThirdsOverlay)
    }

    @objc func toggleRuleOfThirds() {
        coordinator.setRuleOfThirdsOverlayVisible(!coordinator.settings.showsRuleOfThirdsOverlay)
    }

    @objc func zoomIn() {
        coordinator.zoomIn()
    }

    @objc func zoomOut() {
        coordinator.zoomOut()
    }

    @objc func resetZoom() {
        coordinator.resetZoom()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func chooseSceneItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        coordinator.selectScene(id: id)
        windowController?.syncRuleOfThirdsOverlay()
        rebuildMenu()
    }

    @objc func chooseDisplayItem(_ sender: NSMenuItem) {
        coordinator.setDisplay(id: sender.representedObject as? String)
        mainMenuBuilder?.rebuild()
        windowController?.syncRuleOfThirdsOverlay()
    }

    @objc func chooseCameraItem(_ sender: NSMenuItem) {
        coordinator.setCamera(id: sender.representedObject as? String)
        mainMenuBuilder?.rebuild()
    }

    @objc func chooseMicrophoneItem(_ sender: NSMenuItem) {
        coordinator.setMicrophone(id: sender.representedObject as? String)
        mainMenuBuilder?.rebuild()
    }

    @objc func chooseLayoutItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layout = CaptureLayout(rawValue: raw) else { return }
        coordinator.setLayout(layout)
        mainMenuBuilder?.rebuild()
        windowController?.syncRuleOfThirdsOverlay()
    }

    @objc func fitFrontWindowForShorts() {
        coordinator.fitFrontWindowForShorts()
        mainMenuBuilder?.rebuild()
        windowController?.syncRuleOfThirdsOverlay()
    }

    @objc func makeTargetWindowWider() {
        coordinator.resizeTargetWindow(widthDelta: 48, heightDelta: 0)
    }

    @objc func makeTargetWindowNarrower() {
        coordinator.resizeTargetWindow(widthDelta: -48, heightDelta: 0)
    }

    @objc func makeTargetWindowTaller() {
        coordinator.resizeTargetWindow(widthDelta: 0, heightDelta: 48)
    }

    @objc func makeTargetWindowShorter() {
        coordinator.resizeTargetWindow(widthDelta: 0, heightDelta: -48)
    }

    @objc func pickScreen() {
        Task {
            do {
                try await coordinator.pickScreenSource()
                mainMenuBuilder?.rebuild()
            } catch {
                coordinator.onMessage?("Screen picker failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func selectScreenRegion() {
        Task {
            do {
                try await coordinator.selectScreenCrop()
                mainMenuBuilder?.rebuild()
            } catch {
                coordinator.onMessage?("Screen region picker failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func clearScreenRegion() {
        coordinator.clearScreenCrop()
        mainMenuBuilder?.rebuild()
    }

    @objc func openOutputFolder() {
        NSWorkspace.shared.open(coordinator.settings.outputDirectory)
    }

    @objc func revealLastTake() {
        if let take = coordinator.lastTake {
            NSWorkspace.shared.activateFileViewerSelecting([take.finalVideoURL])
        } else {
            NSWorkspace.shared.open(coordinator.settings.outputDirectory)
        }
    }

    @objc func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = coordinator.settings.outputDirectory
        panel.prompt = "Choose"
        panel.message = "Pick the folder where recordings will be saved."
        if panel.runModal() == .OK, let url = panel.url {
            coordinator.setOutputDirectory(url)
            windowController?.syncRuleOfThirdsOverlay()
        }
    }

    @objc func mergeLastTake() {
        coordinator.mergeLastTake()
    }
}

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
