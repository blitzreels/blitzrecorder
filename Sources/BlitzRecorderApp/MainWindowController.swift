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
    private let previewStage = PreviewStageView()
    private let viewModel: RecorderViewModel

    private var cameraDeviceObservers: [NSObjectProtocol] = []
    private var isStartingCameraPreview = false
    private var cameraPreviewDeviceID: String?
    private var preservedHiddenScreenPreviewSelectionRevision: Int?
    private var lastStartedScreenCaptureSignature: ScreenCaptureSignature?
    private var settingsWindowController: SettingsWindowController?
    private var currentRecordingState: RecordingState = .idle
    private var idlePreviewRestartTask: Task<Void, Never>?

    init(coordinator: RecorderCoordinator) {
        self.coordinator = coordinator
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

        coordinator.onAudioLevel = { [weak self] source, level in
            self?.viewModel.appendAudioLevel(level, source: source)
        }
        coordinator.onScreenCaptureConfigurationChanged = { [weak self] in
            self?.restartScreenPreview()
        }
        coordinator.onLiveScreenPreviewFrame = { [weak self] frame in
            guard let self,
                  self.coordinator.settings.visibleSources.contains(.screen) else { return }
            self.previewStage.screenSourceAspectRatio = frame.sourceAspectRatio
            self.previewStage.screenPreview.enqueuePreviewSampleBuffer(frame.sampleBuffer)
        }
        coordinator.onCameraConfigurationChanged = { [weak self] in
            self?.refreshCameraPicker()
        }
        coordinator.onLocalCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  !self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            self.previewStage.cameraPreview.enqueuePreviewSampleBuffer(sampleBuffer, width: width, height: height)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPreviewFrame = { [weak self] image in
            guard let self,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            let aspectRatio = self.viewModel.applyRemoteCameraPreviewImage(image)
            self.previewStage.cameraPreview.setPreviewImage(image, sourceAspectRatio: aspectRatio)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self,
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
            self.refreshStartupState()
            self.startScreenPreview()
            self.startCameraPreview()
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

    func updateRenderProgress(_ progress: Double) {
        viewModel.applyRenderProgress(progress)
    }

    func syncRuleOfThirdsOverlay() {
        viewModel.syncSettings()
    }

    func presentSettings(selecting pane: SettingsPane? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(viewModel: viewModel)
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
        let screenSourceBinding: ScreenSourceBinding?
        let selectedDisplayID: String?
        let screenCrop: CGRect?
        let framesPerSecond: Int
        let includeCursor: Bool
        let isEditingCrop: Bool
    }

    private func currentScreenCaptureSignature() -> ScreenCaptureSignature {
        let settings = coordinator.settings
        return ScreenCaptureSignature(
            usesPickedContent: settings.usesPickedScreenContent,
            selectionRevision: coordinator.screenContentSelectionRevision,
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
        guard coordinator.state == .idle else { return }

        if coordinator.isScreenPreviewRunning,
           coordinator.settings.enabledSources.contains(.screen),
           !coordinator.settings.hiddenSources.contains(.screen),
           currentScreenCaptureSignature() == lastStartedScreenCaptureSignature {
            refreshPermissionGate()
            return
        }

        switch ScreenPreviewLifecycle.action(
            settings: coordinator.settings,
            previewIsRunning: coordinator.isScreenPreviewRunning,
            preservedSelectionRevision: preservedHiddenScreenPreviewSelectionRevision,
            currentSelectionRevision: coordinator.screenContentSelectionRevision
        ) {
        case .preserveHidden:
            preservedHiddenScreenPreviewSelectionRevision = coordinator.isScreenPreviewRunning
                ? coordinator.screenContentSelectionRevision
                : nil
            startScreenPreview()
        case .reusePreserved:
            preservedHiddenScreenPreviewSelectionRevision = nil
            refreshPermissionGate()
        case .restart:
            preservedHiddenScreenPreviewSelectionRevision = nil
            Task {
                await coordinator.stopScreenPreview()
                startScreenPreview()
            }
        }
    }

    func restartCameraPreview() {
        viewModel.syncSettings()
        guard coordinator.state == .idle else { return }
        if coordinator.isRemoteCameraSelected {
            startCameraPreview()
            return
        }
        cameraPreviewDeviceID = nil
        previewStage.cameraPreview.setMessage("Restarting camera")
        Task {
            await coordinator.stopCameraPreview()
            startCameraPreview()
        }
    }

    private func refreshStartupState() {
        Task {
            coordinator.refreshAudioLevelMonitoring()
            await viewModel.refreshSources()
            viewModel.syncSettings()
            refreshPermissionGate()
        }
    }

    private func refreshPermissionGate() {
        guard coordinator.state == .idle else { return }
        let readiness = coordinator.recordingReadiness()
        PermissionGate.writeDiagnostic(readiness)
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
            if coordinator.settings.screenSourceBinding == nil {
                return "Pick a screen to preview, or enable Screen Recording for full capture."
            }
            return "Enable Screen Recording to preview the selected screen source."
        }
        if let blocker = readiness.blockers.first {
            return "\(blocker.source.rawValue) permission required."
        }
        return ""
    }

    private func startScreenPreview() {
        if coordinator.settings.hiddenSources.contains(.screen) {
            previewStage.screenPreview.setMessage("Screen source hidden")
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        guard coordinator.settings.enabledSources.contains(.screen) else {
            Task { await coordinator.stopScreenPreview() }
            previewStage.screenPreview.setMessage("Screen source off")
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        guard coordinator.settings.usesPickedScreenContent || coordinator.hasScreenCaptureAccess() else {
            if coordinator.settings.screenSourceBinding == nil {
                previewStage.screenPreview.setMessage("")
                viewModel.applyMessage("Pick a screen to preview, or enable Screen Recording for full capture.")
            } else {
                previewStage.screenPreview.setMessage("Screen Recording permission required")
                viewModel.applyMessage("Enable Screen Recording to preview the selected screen source.")
            }
            lastStartedScreenCaptureSignature = nil
            refreshPermissionGate()
            return
        }

        if !previewStage.screenPreview.hasPreviewContent {
            previewStage.screenPreview.setMessage("Starting screen preview")
        }
        lastStartedScreenCaptureSignature = currentScreenCaptureSignature()
        Task {
            do {
                try await coordinator.startScreenPreview { [weak self] frame in
                    self?.previewStage.screenSourceAspectRatio = frame.sourceAspectRatio
                    self?.previewStage.screenPreview.enqueuePreviewSampleBuffer(frame.sampleBuffer)
                }
                refreshPermissionGate()
            } catch {
                guard coordinator.state == .idle else { return }
                previewStage.screenPreview.setMessage("Screen preview unavailable")
                viewModel.applyMessage("Screen preview failed: \(error.localizedDescription)")
                lastStartedScreenCaptureSignature = nil
                refreshPermissionGate()
            }
        }
    }

    private func startCameraPreview() {
        if coordinator.settings.hiddenSources.contains(.camera) {
            Task { await coordinator.stopCameraPreview() }
            previewStage.cameraPreview.setMessage("Camera source hidden")
            previewStage.cameraPreview.isHidden = true
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            return
        }

        guard coordinator.settings.enabledSources.contains(.camera) else {
            Task { await coordinator.stopCameraPreview() }
            previewStage.cameraPreview.setMessage("Camera source off")
            previewStage.cameraPreview.isHidden = true
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            return
        }

        let selectedID = coordinator.settings.selectedCameraID
        if coordinator.isRemoteCameraSelected {
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

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Allow Camera to preview")
            cameraPreviewDeviceID = nil
            guard !isStartingCameraPreview else {
                refreshPermissionGate()
                return
            }
            isStartingCameraPreview = true
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                isStartingCameraPreview = false
                if granted {
                    startCameraPreview()
                } else {
                    previewStage.cameraPreview.setMessage("Camera permission required")
                }
                refreshPermissionGate()
            }
            refreshPermissionGate()
            return
        case .denied, .restricted:
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Camera permission required")
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            refreshPermissionGate()
            return
        @unknown default:
            previewStage.cameraPreview.isHidden = false
            previewStage.cameraPreview.setMessage("Camera unavailable")
            cameraPreviewDeviceID = nil
            isStartingCameraPreview = false
            refreshPermissionGate()
            return
        }

        if isStartingCameraPreview, cameraPreviewDeviceID == selectedID { return }
        if previewStage.cameraPreview.hasPreviewContent, cameraPreviewDeviceID == selectedID { return }

        previewStage.cameraPreview.isHidden = false
        cameraPreviewDeviceID = selectedID
        isStartingCameraPreview = true
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
                    guard coordinator.settings.visibleSources.contains(.camera) else {
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
                refreshPermissionGate()
            } catch {
                isStartingCameraPreview = false
                cameraPreviewDeviceID = nil
                previewStage.cameraPreview.setMessage("Camera unavailable")
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
            AVCaptureDevice.wasDisconnectedNotification,
            NSApplication.didBecomeActiveNotification
        ]

        cameraDeviceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if let device = notification.object as? AVCaptureDevice,
                   !device.hasMediaType(.video) {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.refreshCameraPicker()
                }
            }
        }
    }
}
