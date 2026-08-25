import AppKit
import AVFoundation
import CoreImage
import SwiftUI

enum Brand {
    static let background = NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.055, alpha: 1)
    static let card = NSColor(calibratedRed: 0.039, green: 0.039, blue: 0.039, alpha: 1)
    static let elevated = NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.075, alpha: 1)
    static let border = NSColor.white.withAlphaComponent(0.08)
    static let primary = NSColor(calibratedRed: 0.09, green: 1.0, blue: 0.65, alpha: 1)
    static let foreground = NSColor(calibratedWhite: 0.98, alpha: 1)
    static let muted = NSColor.white.withAlphaComponent(0.52)
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let coordinator: RecorderCoordinator
    private let mcpServer: BlitzRecorderMCPServer
    private let previewStage = PreviewStageView()
    private let viewModel: RecorderViewModel

    private var cameraDeviceObservers: [NSObjectProtocol] = []
    private var isStartingCameraPreview = false
    private var cameraPreviewDeviceID: String?
    private var cameraPreviewStartRevision = 0
    private var initialSupportingCaptureResourcesTask: Task<Void, Never>?
    private var initialSupportingCaptureResourcesStarted = false
    private var lastStartedScreenCaptureSignature: ScreenCaptureSignature?
    private var screenPreviewStartRevision = 0
    private var screenPreviewWatchdogTask: Task<Void, Never>?
    private var screenPreviewRecoverySignature: ScreenCaptureSignature?
    private var screenPreviewRecoveryAttempts = 0
    private var settingsWindowController: SettingsWindowController?
    private var currentRecordingState: RecordingState = .idle
    private var idlePreviewRestartTask: Task<Void, Never>?
    private var studioModeCaptureResourceTask: Task<Void, Never>?
    var onEditorHistoryChanged: (() -> Void)? {
        didSet {
            viewModel.onEditorHistoryChanged = onEditorHistoryChanged
        }
    }

    var canUndoEditor: Bool { viewModel.canUndoEditor }
    var canRedoEditor: Bool { viewModel.canRedoEditor }
    var editorUndoTitle: String { viewModel.editorUndoTitle }
    var editorRedoTitle: String { viewModel.editorRedoTitle }

    struct Configuration {
        let coordinator: RecorderCoordinator
        let mcpServer: BlitzRecorderMCPServer
    }

    init(_ configuration: Configuration) {
        let coordinator = configuration.coordinator
        self.coordinator = coordinator
        self.mcpServer = configuration.mcpServer
        self.viewModel = RecorderViewModel(
            coordinator: coordinator,
            previewStage: previewStage
        )

        let window = NSWindow(
            contentRect: Self.initialContentRect(),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlitzRecorder"
        window.sharingType = .readOnly
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = Self.minimumWindowContentSize
        window.backgroundColor = .black
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)

        window.delegate = self

        viewModel.onPresentSettings = { [weak self] pane in
            self?.presentSettings(selecting: pane)
        }
        viewModel.onFillEditorWindow = { [weak self] in
            self?.fillEditorWindow()
        }
        viewModel.onStudioModeChanged = { [weak self] mode in
            self?.syncIdleCaptureResources(for: mode)
        }
        viewModel.onProjectOpened = { [weak self] in
            self?.showEditorAfterOpeningProject()
        }
        coordinator.onAudioLevel = { [weak self] source, level in
            self?.viewModel.appendAudioLevel(level, source: source)
        }
        coordinator.onScreenCaptureConfigurationChanged = { [weak self] in
            self?.restartScreenPreview()
        }
        coordinator.onLiveScreenPreviewFrame = { [weak self] frame in
            guard let self,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive,
                  self.coordinator.settings.visibleSources.contains(.screen) else { return }
            self.previewStage.screenSourceAspectRatio = frame.sourceAspectRatio
            self.previewStage.screenPreview.enqueuePreviewSampleBuffer(frame.sampleBuffer)
        }
        coordinator.onCameraConfigurationChanged = { [weak self] in
            self?.refreshCameraPicker()
        }
        coordinator.onLocalCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  !self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            self.previewStage.cameraPreview.enqueuePreviewSampleBuffer(sampleBuffer, width: width, height: height)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPreviewFrame = { [weak self] image in
            guard let self,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            let aspectRatio = self.viewModel.applyRemoteCameraPreviewImage(image)
            self.previewStage.cameraPreview.setPreviewImage(image, sourceAspectRatio: aspectRatio)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            let aspectRatio = self.viewModel.applyRemoteCameraPreviewSampleBuffer(
                sampleBuffer,
                width: width,
                height: height
            )
            self.previewStage.cameraPreview.enqueuePreviewSampleBuffer(
                sampleBuffer,
                width: width,
                height: height,
                sourceAspectRatio: aspectRatio
            )
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPreviewReset = { [weak self] message in
            guard let self,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            self.previewStage.cameraPreview.setMessage(message)
            self.viewModel.clearRemoteCameraPreview(message: message)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPairingCodeRequested = { [weak self] deviceName in
            self?.requestRemoteCameraPairingCode(deviceName: deviceName)
        }

        previewStage.captureLayout = coordinator.settings.layout
        previewStage.enabledSources = coordinator.settings.visibleSources
        previewStage.sceneLayout = coordinator.settings.sceneLayout
        previewStage.screenSourceAspectRatio = coordinator.currentScreenSourceAspectRatio()
        previewStage.showsRuleOfThirdsOverlay = coordinator.settings.showsRuleOfThirdsOverlay
        previewStage.socialSafeZoneOverlay = coordinator.settings.socialSafeZoneOverlay
        previewStage.canvasBackgroundStyle = coordinator.settings.canvasBackgroundStyle
        previewStage.canvasPadding = coordinator.settings.canvasPadding

        let host = NSHostingView(rootView: MainView(vm: viewModel).preferredColorScheme(.dark))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.contentMinSize = Self.minimumWindowContentSize
        window.minSize = Self.minimumWindowContentSize

        viewModel.applyState(coordinator.state)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startCameraDeviceMonitoring()
            if LocalDevelopmentRuntime.disablesIdleCapture() {
                self.viewModel.syncSettings()
                self.refreshPermissionGate()
                return
            }
            self.startCameraPreview()
            self.scheduleInitialSupportingCaptureResources(after: .seconds(4))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minSize = Self.minimumWindowContentSize
        return NSSize(
            width: max(frameSize.width, minSize.width),
            height: max(frameSize.height, minSize.height)
        )
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard currentRecordingState.allowsWindowClose else {
            viewModel.applyMessage("Stop the recording before closing BlitzRecorder.")
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        suspendIdleCaptureResources()
        viewModel.prepareForWindowClose()
    }

    static let minimumWindowContentSize = NSSize(width: 1120, height: 760)

    private static func initialContentRect() -> NSRect {
        let fallback = NSRect(x: 0, y: 0, width: 1200, height: 820)
        let environment = ProcessInfo.processInfo.environment
        guard environment["BLITZRECORDER_SCREENSHOT_MODE"] == "1",
              let size = environment["BLITZRECORDER_SCREENSHOT_WINDOW_SIZE"] else {
            return fallback
        }

        let parts = size.split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width >= 1040,
              height >= 720 else {
            return fallback
        }

        return NSRect(x: 0, y: 0, width: width, height: height)
    }

    deinit {
        idlePreviewRestartTask?.cancel()
        initialSupportingCaptureResourcesTask?.cancel()
        screenPreviewWatchdogTask?.cancel()
        for observer in cameraDeviceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func update(for state: RecordingState) {
        let previousState = currentRecordingState
        currentRecordingState = state
        viewModel.applyState(state)
        switch state {
        case .idle:
            refreshPermissionGate()
            scheduleIdlePreviewRestart(afterNanoseconds: IdlePreviewRestartPolicy.delayNanoseconds(
                previousState: previousState,
                newState: state
            ))
        case .recording, .paused:
            cancelScheduledIdlePreviewRestart()
            showRecordingCameraPreview()
        case .starting, .finishing:
            cancelScheduledIdlePreviewRestart()
            break
        }
    }

    private func scheduleIdlePreviewRestart(afterNanoseconds delayNanoseconds: UInt64) {
        idlePreviewRestartTask?.cancel()
        idlePreviewRestartTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self,
                  !Task.isCancelled,
                  self.coordinator.state == .idle else {
                return
            }
            self.restartScreenPreview()
            self.restartCameraPreview()
            self.idlePreviewRestartTask = nil
        }
    }

    private func cancelScheduledIdlePreviewRestart() {
        idlePreviewRestartTask?.cancel()
        idlePreviewRestartTask = nil
    }

    func setDetail(_ message: String) {
        viewModel.applyMessage(message)
        if message.hasPrefix("Start failed:") {
            showStartFailureAlert(message)
        } else if message.hasPrefix("Recording failed:") {
            showRecordingFailureAlert(message)
        } else if message.hasPrefix("Stop failed:") || message.hasPrefix("Final video export failed:") {
            showRecordingFailureAlert(message)
        }
    }

    func applySavedRecordingOutput(_ output: SavedRecordingOutput) {
        viewModel.applySavedRecordingOutput(output)
    }

    func applyPostRecordingProjectOutput(_ output: PostRecordingProjectOutput) {
        viewModel.applyPostRecordingProjectOutput(output)
    }

    func openProject(_ project: RecordingProjectHistory.Entry) {
        viewModel.openProject(project)
    }

    func applyRecoveryOutput(_ output: RecordingRecoveryOutput) {
        viewModel.applyRecoveryOutput(output)
    }

    private func showStartFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording did not start"
        alert.informativeText = String(message.dropFirst("Start failed:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showRecordingFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording did not save"
        alert.informativeText = message
            .replacingOccurrences(of: "Recording failed:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func requestRemoteCameraPairingCode(deviceName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Pair \(deviceName)"
        alert.informativeText = "Enter the 6-digit code shown on the iPhone."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Pair")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "123456"
        input.alignment = .center
        input.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        alert.accessoryView = input

        window?.makeKeyAndOrderFront(nil)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }
        return input.stringValue
    }

    func applyExportFailure(_ message: String?) {
        viewModel.applyExportFailure(message)
    }

    func undoEditor() {
        viewModel.undoEditor()
    }

    func redoEditor() {
        viewModel.redoEditor()
    }

    func updateRenderProgress(_ progress: Double) {
        viewModel.applyRenderProgress(progress)
    }

    func syncRuleOfThirdsOverlay() {
        viewModel.syncSettings()
    }

    func presentSettings(selecting pane: SettingsPane? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(.init(
                viewModel: viewModel,
                mcpServer: mcpServer
            ))
        }
        if let pane {
            settingsWindowController?.select(pane)
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.settingsWindowController?.window else { return }
            self?.settingsWindowController?.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func showEditorAfterOpeningProject() {
        settingsWindowController?.close()
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
    }

    private func fillEditorWindow() {
        guard let window,
              let visibleFrame = window.screen?.visibleFrame else {
            return
        }
        window.setFrame(visibleFrame, display: true, animate: true)
    }

    private func syncIdleCaptureResources(for mode: RecorderViewModel.StudioMode) {
        if mode.keepsIdleCaptureResourcesActive {
            resumeIdleCaptureResources()
        } else {
            suspendIdleCaptureResources()
        }
    }

    private func resumeIdleCaptureResources() {
        guard !LocalDevelopmentRuntime.disablesIdleCapture() else { return }
        let previousTask = studioModeCaptureResourceTask
        studioModeCaptureResourceTask = Task { @MainActor [weak self] in
            _ = await previousTask?.result
            guard let self,
                  NSApp.isActive,
                  self.window?.isVisible == true,
                  self.coordinator.state == .idle,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }
            await coordinator.resumeIdleAudioLevelMonitoring()
            guard NSApp.isActive,
                  self.window?.isVisible == true,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }
            startScreenPreview()
            startCameraPreview()
        }
    }

    private func suspendIdleCaptureResources() {
        guard coordinator.state == .idle else { return }
        cancelScheduledIdlePreviewRestart()
        screenPreviewStartRevision += 1
        screenPreviewWatchdogTask?.cancel()
        screenPreviewWatchdogTask = nil
        lastStartedScreenCaptureSignature = nil
        invalidateCameraPreviewStart()
        let previousTask = studioModeCaptureResourceTask
        studioModeCaptureResourceTask = Task { [weak self] in
            _ = await previousTask?.result
            guard let self, self.coordinator.state == .idle else { return }
            await coordinator.suspendIdleCaptureResources()
        }
    }

    private func invalidateCameraPreviewStart() {
        cameraPreviewStartRevision += 1
        isStartingCameraPreview = false
        cameraPreviewDeviceID = nil
    }

    func writeScreenshot(to url: URL) throws {
        guard let view = window?.contentView else {
            throw CocoaError(.fileWriteUnknown)
        }

        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }

        representation.size = bounds.size
        view.cacheDisplay(in: bounds, to: representation)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try data.write(to: url, options: .atomic)
    }

    private struct ScreenCaptureSignature: Equatable {
        let usesPickedContent: Bool
        let selectionRevision: Int
        let windowGeometryRevision: Int
        let screenSourceBinding: ScreenSourceBinding?
        let selectedDisplayID: String?
        let screenCrop: CGRect?
        let framesPerSecond: Int
        let includeCursor: Bool
        let isEditingCrop: Bool
    }

    private struct ScreenPreviewWatchdogRequest {
        let startRevision: Int
    }

    private func currentScreenCaptureSignature() -> ScreenCaptureSignature {
        let settings = coordinator.settings
        return ScreenCaptureSignature(
            usesPickedContent: settings.usesPickedScreenContent,
            selectionRevision: coordinator.screenContentSelectionRevision,
            windowGeometryRevision: coordinator.screenWindowGeometryRevision,
            screenSourceBinding: settings.screenSourceBinding,
            selectedDisplayID: settings.selectedDisplayID,
            screenCrop: settings.screenCrop,
            framesPerSecond: settings.framesPerSecond,
            includeCursor: settings.includeCursor,
            isEditingCrop: viewModel.isScreenCropModeEnabled
        )
    }

    func restartScreenPreview() {
        viewModel.syncSettings()
        guard coordinator.state == .idle,
              viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }

        if ScreenPreviewLifecycle.shouldReuse(.init(
            isRunning: coordinator.isScreenPreviewRunning,
            hasPreviewContent: previewStage.screenPreview.hasPreviewContent,
            screenEnabled: coordinator.settings.enabledSources.contains(.screen),
            screenHidden: coordinator.settings.hiddenSources.contains(.screen),
            captureSignatureMatches: currentScreenCaptureSignature() == lastStartedScreenCaptureSignature
        )) {
            refreshPermissionGate()
            return
        }

        switch ScreenPreviewLifecycle.action(settings: coordinator.settings) {
        case .preserveHidden:
            startScreenPreview()
        case .restart:
            Task {
                await coordinator.stopScreenPreview()
                guard viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }
                startScreenPreview()
            }
        }
    }

    func restartCameraPreview() {
        viewModel.syncSettings()
        guard coordinator.state == .idle,
              viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }
        if coordinator.isRemoteCameraSelected {
            startCameraPreview()
            return
        }
        invalidateCameraPreviewStart()
        previewStage.cameraPreview.setMessage("Restarting camera")
        Task {
            await coordinator.stopCameraPreview()
            guard viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }
            startCameraPreview()
        }
    }

    private func refreshStartupState() {
        Task {
            coordinator.refreshAudioLevelMonitoring()
            viewModel.syncSettings()
            refreshPermissionGate()
        }
    }

    private func scheduleInitialSupportingCaptureResources(after delay: Duration) {
        guard !initialSupportingCaptureResourcesStarted else { return }
        initialSupportingCaptureResourcesTask?.cancel()
        initialSupportingCaptureResourcesTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            initialSupportingCaptureResourcesTask = nil
            startInitialSupportingCaptureResources()
        }
    }

    private func startInitialSupportingCaptureResources() {
        guard !initialSupportingCaptureResourcesStarted else { return }
        initialSupportingCaptureResourcesStarted = true
        initialSupportingCaptureResourcesTask?.cancel()
        initialSupportingCaptureResourcesTask = nil
        refreshStartupState()
        startScreenPreview()
    }

    private func refreshPermissionGate() {
        guard coordinator.state == .idle else { return }
        let readiness = coordinator.recordingReadiness()
        coordinator.permissionGate.writeDiagnostic(readiness)
        if !readiness.isReady {
            viewModel.applyMessage(shortReadinessMessage(readiness))
        } else if viewModel.detailMessage.hasPrefix("Screen permission") ||
                  viewModel.detailMessage.hasPrefix("Share a screen") ||
                  viewModel.detailMessage.hasPrefix("Pick a screen") ||
                  viewModel.detailMessage.hasPrefix("Enable BlitzRecorder") {
            viewModel.applyMessage("")
        }
    }

    private func shortReadinessMessage(_ readiness: RecordingReadiness) -> String {
        if readiness.isReady { return "" }
        if readiness.blockers.contains(where: { $0.source == .screen || $0.source == .systemAudio }) {
            if coordinator.settings.screenSourceBinding?.isConcreteSelection != true {
                return "Enable Screen Recording, then choose a screen source."
            }
            return "Enable Screen Recording to preview the selected source."
        }
        if let blocker = readiness.blockers.first {
            if blocker.permission == "Camera availability" {
                return blocker.status == "starting"
                    ? "Starting camera preview."
                    : "Camera unavailable. Choose another camera or close the app using it."
            }
            return "\(blocker.source.rawValue) permission required."
        }
        return ""
    }

    private func startScreenPreview() {
        guard !LocalDevelopmentRuntime.disablesIdleCapture() else { return }
        guard viewModel.studioMode.keepsIdleCaptureResourcesActive else { return }
        if coordinator.settings.hiddenSources.contains(.screen) {
            screenPreviewWatchdogTask?.cancel()
            screenPreviewWatchdogTask = nil
            refreshPermissionGate()
            return
        }

        guard coordinator.settings.enabledSources.contains(.screen) else {
            screenPreviewStartRevision += 1
            screenPreviewWatchdogTask?.cancel()
            screenPreviewWatchdogTask = nil
            Task { await coordinator.stopScreenPreview() }
            previewStage.screenPreview.setMessage("Screen source off")
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        guard coordinator.hasActiveScreenSourceSelection else {
            screenPreviewStartRevision += 1
            screenPreviewWatchdogTask?.cancel()
            screenPreviewWatchdogTask = nil
            previewStage.screenPreview.setMessage("")
            viewModel.applyMessage("Choose a screen, app, or window to preview.")
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        if !previewStage.screenPreview.hasPreviewContent {
            previewStage.screenPreview.setMessage("Starting screen preview")
        }
        let captureSignature = currentScreenCaptureSignature()
        if screenPreviewRecoverySignature != captureSignature {
            screenPreviewRecoverySignature = captureSignature
            screenPreviewRecoveryAttempts = 0
        }
        lastStartedScreenCaptureSignature = captureSignature
        screenPreviewStartRevision += 1
        let previewStartRevision = screenPreviewStartRevision
        let previewSettings = coordinator.settings
        scheduleScreenPreviewWatchdog(.init(startRevision: previewStartRevision))
        Task { [weak self] in
            guard let self else { return }
            do {
                try await coordinator.startScreenPreview { [weak self] frame in
                    guard let self, self.screenPreviewStartRevision == previewStartRevision else { return }
                    self.screenPreviewRecoveryAttempts = 0
                    self.screenPreviewWatchdogTask?.cancel()
                    self.screenPreviewWatchdogTask = nil
                    self.previewStage.screenSourceAspectRatio = frame.sourceAspectRatio
                    self.previewStage.screenPreview.enqueuePreviewSampleBuffer(frame.sampleBuffer)
                }
                guard self.screenPreviewStartRevision == previewStartRevision else { return }
                refreshPermissionGate()
            } catch {
                guard self.screenPreviewStartRevision == previewStartRevision,
                      coordinator.state == .idle else { return }
                previewStage.screenPreview.setMessage("")
                viewModel.applyMessage(
                    ScreenPreviewFailureMessage.detailMessage(for: error, settings: previewSettings)
                )
                lastStartedScreenCaptureSignature = nil
                refreshPermissionGate()
            }
        }
    }

    private func scheduleScreenPreviewWatchdog(_ request: ScreenPreviewWatchdogRequest) {
        screenPreviewWatchdogTask?.cancel()
        screenPreviewWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self,
                  !Task.isCancelled,
                  self.screenPreviewStartRevision == request.startRevision,
                  self.coordinator.state == .idle,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive,
                  self.coordinator.settings.visibleSources.contains(.screen),
                  !self.previewStage.screenPreview.hasPreviewContent else { return }

            self.screenPreviewStartRevision += 1
            self.lastStartedScreenCaptureSignature = nil
            if self.screenPreviewRecoveryAttempts >= 2 {
                self.previewStage.screenPreview.setMessage("Screen preview unavailable")
                self.viewModel.applyMessage(
                    "Screen preview stopped responding. Re-select the screen source to reconnect."
                )
                self.screenPreviewWatchdogTask = nil
                return
            }

            self.screenPreviewRecoveryAttempts += 1
            self.previewStage.screenPreview.setMessage("Restarting screen preview")
            await self.coordinator.stopScreenPreview()
            try? await Task.sleep(for: .milliseconds(250))
            guard self.coordinator.state == .idle,
                  self.viewModel.studioMode.keepsIdleCaptureResourcesActive,
                  self.coordinator.settings.visibleSources.contains(.screen) else { return }
            self.startScreenPreview()
        }
    }

    private func startCameraPreview() {
        guard !LocalDevelopmentRuntime.disablesIdleCapture() else { return }
        let request = IdleCameraPreviewRequest(
            appIsActive: NSApp.isActive,
            windowIsVisible: window?.isVisible == true,
            keepsIdleCaptureResourcesActive: viewModel.studioMode.keepsIdleCaptureResourcesActive,
            cameraIsRunningSomewhere: false
        )
        guard IdleCameraPreviewPolicy.shouldStart(request) else { return }
        if coordinator.settings.hiddenSources.contains(.camera) {
            coordinator.setLocalCameraRuntimeState(.unchecked)
            Task { await coordinator.stopCameraPreview() }
            previewStage.cameraPreview.setMessage("Camera source hidden")
            previewStage.cameraPreview.isHidden = true
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            return
        }

        guard coordinator.settings.enabledSources.contains(.camera) else {
            coordinator.setLocalCameraRuntimeState(.unchecked)
            Task { await coordinator.stopCameraPreview() }
            previewStage.cameraPreview.setMessage("Camera source off")
            previewStage.cameraPreview.isHidden = true
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            return
        }

        let selectedID = coordinator.settings.selectedCameraID
        if coordinator.isRemoteCameraSelected {
            coordinator.setLocalCameraRuntimeState(.unchecked)
            previewStage.cameraPreview.isHidden = false
            cameraPreviewDeviceID = selectedID
            let name = coordinator.selectedRemoteCameraName() ?? "Remote iPhone"
            let status = coordinator.selectedRemoteCameraStatus() ?? "Waiting for iPhone video"
            switch coordinator.selectedRemoteCameraConnectionState() {
            case .connected:
                if previewStage.cameraPreview.hasPreviewContent {
                    refreshPermissionGate()
                    return
                }
            case .pairing, .degraded, .disconnected, .discovering, .unavailable, nil:
                previewStage.cameraPreview.setMessage("\(name): \(status)")
                viewModel.clearRemoteCameraPreview(message: status)
                refreshPermissionGate()
                return
            }
            previewStage.cameraPreview.setMessage("\(name): \(status)")
            refreshPermissionGate()
            return
        }

        switch coordinator.permissionGate.cameraAuthorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            coordinator.setLocalCameraRuntimeState(.unchecked)
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Allow Camera to preview")
            cameraPreviewDeviceID = nil
            guard !isStartingCameraPreview else {
                refreshPermissionGate()
                return
            }
            isStartingCameraPreview = true
            Task {
                let granted = await coordinator.permissionGate.requestCameraAccess()
                isStartingCameraPreview = false
                if granted, viewModel.studioMode.keepsIdleCaptureResourcesActive {
                    startCameraPreview()
                } else {
                    previewStage.cameraPreview.setMessage("Camera permission required")
                }
                refreshPermissionGate()
            }
            refreshPermissionGate()
            return
        case .denied, .restricted:
            coordinator.setLocalCameraRuntimeState(.unchecked)
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Camera permission required")
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            refreshPermissionGate()
            return
        @unknown default:
            coordinator.setLocalCameraRuntimeState(.unavailable("Camera authorization is unavailable"))
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Camera unavailable")
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            refreshPermissionGate()
            return
        }

        if isStartingCameraPreview, cameraPreviewDeviceID == selectedID {
            coordinator.setLocalCameraRuntimeState(.starting)
            return
        }
        if previewStage.cameraPreview.hasPreviewContent, cameraPreviewDeviceID == selectedID {
            coordinator.setLocalCameraRuntimeState(.ready)
            refreshPermissionGate()
            return
        }

        previewStage.cameraPreview.isHidden = false
        cameraPreviewDeviceID = selectedID
        isStartingCameraPreview = true
        cameraPreviewStartRevision += 1
        let startRevision = cameraPreviewStartRevision
        coordinator.setLocalCameraRuntimeState(.starting)
        refreshPermissionGate()
        if !previewStage.cameraPreview.hasPreviewContent {
            previewStage.cameraPreview.setMessage("Starting camera")
        }
        Task {
            do {
                if coordinator.settings.removesCameraBackgroundAfterRecording {
                    previewStage.cameraPreview.setMessage("Starting cutout")
                    try await coordinator.startCameraCutoutPreview { [weak self] image in
                        guard let self,
                              self.coordinator.settings.visibleSources.contains(.camera) else {
                            return
                        }
                        self.previewStage.cameraPreview.setPreviewImage(image)
                    }
                } else {
                    let layer = try await coordinator.cameraPreviewLayer()
                    let completionRequest = IdleCameraPreviewRequest(
                        appIsActive: NSApp.isActive,
                        windowIsVisible: window?.isVisible == true,
                        keepsIdleCaptureResourcesActive: viewModel.studioMode.keepsIdleCaptureResourcesActive,
                        cameraIsRunningSomewhere: false
                    )
                    guard cameraPreviewStartRevision == startRevision,
                          IdleCameraPreviewPolicy.shouldStart(completionRequest),
                          coordinator.settings.visibleSources.contains(.camera) else {
                        await coordinator.stopCameraPreview()
                        previewStage.cameraPreview.setMessage("Camera source off")
                        previewStage.cameraPreview.isHidden = true
                        cameraPreviewDeviceID = nil
                        isStartingCameraPreview = false
                        return
                    }
                    previewStage.cameraPreview.setPreviewLayer(layer)
                }
                isStartingCameraPreview = false
                cameraPreviewDeviceID = coordinator.settings.selectedCameraID
                coordinator.setLocalCameraRuntimeState(.ready)
                scheduleInitialSupportingCaptureResources(after: .seconds(1))
                refreshPermissionGate()
            } catch {
                isStartingCameraPreview = false
                cameraPreviewDeviceID = nil
                previewStage.cameraPreview.setMessage("Camera unavailable")
                coordinator.setLocalCameraRuntimeState(.unavailable(error.localizedDescription))
                viewModel.applyMessage("Camera preview failed: \(error.localizedDescription)")
                refreshPermissionGate()
            }
        }
    }

    private func showRecordingCameraPreview() {
        guard coordinator.settings.visibleSources.contains(.camera) else {
            return
        }
        if coordinator.isRemoteCameraSelected {
            if !previewStage.cameraPreview.hasPreviewContent {
                previewStage.cameraPreview.setMessage("Remote iPhone recording")
            }
            return
        }
        guard coordinator.settings.removesCameraBackgroundAfterRecording else { return }
        cameraPreviewDeviceID = nil
        previewStage.cameraPreview.setMessage("Camera live")
        Task {
            do {
                let layer = try await coordinator.cameraPreviewLayer()
                previewStage.cameraPreview.setPreviewLayer(layer)
                cameraPreviewDeviceID = coordinator.settings.selectedCameraID
            } catch {
                previewStage.cameraPreview.setMessage("Camera recording")
            }
        }
    }

    private func refreshCameraPicker() {
        viewModel.refreshPermissionStatus()
        Task {
            await viewModel.refreshSources()
            viewModel.refreshRemoteCameraState()
            startCameraPreview()
            refreshPermissionGate()
        }
    }

    private func startCameraDeviceMonitoring() {
        let center = NotificationCenter.default
        let names = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ]

        cameraDeviceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice else { return }
                if device.hasMediaType(.audio) {
                    Task { @MainActor [weak self] in
                        await self?.viewModel.refreshSources()
                    }
                    return
                }
                guard device.hasMediaType(.video) else { return }
                Task { @MainActor [weak self] in
                    self?.refreshCameraPicker()
                }
            }
        }
        cameraDeviceObservers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeIdleCaptureResources()
            }
        })
        cameraDeviceObservers.append(center.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendIdleCaptureResources()
            }
        })
    }
}
