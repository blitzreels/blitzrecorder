import AppKit
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, MenuActionsTarget {
    let accessController = AccessController()
    lazy var coordinator = RecorderCoordinator(accessController: accessController)
    var windowController: MainWindowController?
    var statusItem: NSStatusItem?
    var recordingAppIcon: RecordingAppIconController?
    var recordingStatusMenuItem: NSMenuItem?
    var blinkTimer: Timer?
    var statusElapsedTimer: Timer?
    var statusElapsedStartedAt: Date?
    var statusElapsedAccumulated: TimeInterval = 0
    var blinkOn = false
    var mainMenuBuilder: MainMenuBuilder?
    lazy var updateController = AppUpdateController()
    private lazy var mcpServer = BlitzRecorderMCPServer(coordinator: coordinator)
    private var terminationTask: Task<Void, Never>?

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

        NSApp.setActivationPolicy(.regular)
        applyDevIconBadgeIfNeeded()
        recordingAppIcon = RecordingAppIconController(.init(
            baseImage: NSApp.applicationIconImage,
            applyImage: { image in
                NSApp.applicationIconImage = image
                NSApp.dockTile.display()
            }
        ))
        if !LocalDevelopmentRuntime.disablesIdleCapture(), LivePreviewPreference().isEnabled {
            coordinator.prewarmLocalCameraPreviewIfAuthorized()
        }

        let windowController = MainWindowController(.init(
            coordinator: coordinator,
            mcpServer: mcpServer,
            updateController: updateController
        ))
        self.windowController = windowController
        windowController.onEditorHistoryChanged = { [weak self] in
            self?.mainMenuBuilder?.rebuild()
        }

        coordinator.onStateChanged = { [weak self] state in
            self?.updateController.installationBlockedReason = state != .idle
                ? "Finish recording before restarting."
                : self?.coordinator.isExporting == true ? "Finish exporting before restarting." : nil
            if state == .starting { NowPlayingController.shared.suspendForRecording() }
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
        coordinator.onCaptureStopProgress = { [weak self] progress in
            self?.windowController?.updateCaptureStopProgress(progress)
        }
        coordinator.onExportProgress = { [weak self] progress in
            self?.windowController?.viewModel.exportProgress = min(1, max(0, progress))
        }
        coordinator.onExportProjectChanged = { [weak self] projectURL in
            self?.windowController?.viewModel.applyExportProject(projectURL)
            self?.updateController.installationBlockedReason = self?.coordinator.state != .idle
                ? "Finish recording before restarting."
                : projectURL != nil ? "Finish exporting before restarting." : nil
        }
        coordinator.onRenderProgress = { [weak self] progress in
            self?.windowController?.updateRenderProgress(progress)
        }
        coordinator.onExportFailure = { [weak self] message in
            self?.windowController?.applyExportFailure(message)
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
        updateController.onStateChange = { [weak self] in
            self?.mainMenuBuilder?.rebuild()
        }

        buildStatusItem()
        updateStatusItem(for: coordinator.state)
        Task {
            await mcpServer.start()
        }
        if !LocalDevelopmentRuntime.isNoninteractiveVerification() {
            presentMainWindow()
            updateController.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.presentMainWindow()
            }
        }
        writeScreenshotIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        coordinator.permissionGate.stopRequestingPermissions()
        windowController?.cancelPendingPermissionRequests()
        terminationTask = Task { [weak self, weak sender] in
            guard let self else {
                sender?.reply(toApplicationShouldTerminate: true)
                return
            }
            await coordinator.shutdown()
            await mcpServer.stop()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !LocalDevelopmentRuntime.isNoninteractiveVerification() else { return true }
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
        guard !LocalDevelopmentRuntime.isNoninteractiveVerification() else { return }
        if windowController?.window?.isVisible != true {
            presentMainWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            accessController.handleBlitzRecorderURL(url)
        }
    }

    private func applyDevIconBadgeIfNeeded() {
#if DEBUG
        guard ProcessInfo.processInfo.environment["BLITZRECORDER_HIDE_DEV_ICON"] != "1" else { return }
#else
        guard Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true else { return }
#endif
        guard let base = devIconBaseImage() else { return }
        NSApp.applicationIconImage = DevAppIcon.tinted(base)
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

    func presentMainWindow() {
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
        if window.canBecomeMain {
            window.makeMain()
        }
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
}
