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
    let coordinator: RecorderCoordinator
    private let mcpServer: BlitzRecorderMCPServer
    let previewStage = PreviewStageView()
    let viewModel: RecorderViewModel

    var cameraDeviceObservers: [NSObjectProtocol] = []
    var isStartingCameraPreview = false
    var cameraPreviewDeviceID: String?
    var cameraPreviewStartRevision = 0
    var cameraPreviewWatchdogTask: Task<Void, Never>?
    var cameraPreviewRecoveryAttempts = 0
    var lastStartedScreenCaptureSignature: ScreenCaptureSignature?
    var screenPreviewStartRevision = 0
    var screenPreviewWatchdogTask: Task<Void, Never>?
    var screenPreviewRecoverySignature: ScreenCaptureSignature?
    var screenPreviewRecoveryAttempts = 0
    private var currentRecordingState: RecordingState = .idle
    private lazy var recordingHUD = RecordingHUDController(viewModel: viewModel)
    var idlePreviewRestartTask: Task<Void, Never>?
    var studioModeCaptureResourceTask: Task<Void, Never>?
    var idlePreviewIsAllowed: Bool {
        viewModel.studioMode.keepsIdleCaptureResourcesActive && viewModel.isLivePreviewEnabled
    }

    private var previewFramesAreAllowed: Bool {
        viewModel.studioMode.keepsIdleCaptureResourcesActive
            && (coordinator.state != .idle || viewModel.isLivePreviewEnabled)
    }

    private var remoteCameraPreviewFramesAreAllowed: Bool {
        previewFramesAreAllowed
            && coordinator.settings.visibleSources.contains(.camera)
            && coordinator.isRemoteCameraSelected
    }
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
        let updateController: AppUpdateController
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
        MainWindowChrome.configure(window)
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = Self.minimumWindowContentSize
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)

        window.delegate = self

        viewModel.onPresentSettings = { [weak self] pane in
            self?.presentSettings(selecting: pane)
        }
        viewModel.onRetryCameraPreview = { [weak self] in
            self?.restartCameraPreview()
        }
        viewModel.onFillEditorWindow = { [weak self] in
            self?.fillEditorWindow()
        }
        viewModel.onStudioModeChanged = { [weak self] mode in
            self?.syncIdleCaptureResources(for: mode)
            self?.saveStudioPage()
        }
        viewModel.onLivePreviewChanged = { [weak self] _ in
            guard let self else { return }
            self.syncIdleCaptureResources(for: self.viewModel.studioMode)
        }
        viewModel.onProjectOpened = { [weak self] in
            self?.showEditorAfterOpeningProject()
            self?.saveStudioPage()
        }
        coordinator.onAudioLevel = { [weak self] source, level in
            guard let self,
                  self.coordinator.state != .idle || self.viewModel.isLivePreviewEnabled else { return }
            self.viewModel.appendAudioLevel(level, source: source)
        }
        coordinator.onScreenCaptureConfigurationChanged = { [weak self] in
            layoutLog.notice("screen capture configuration changed, restarting preview")
            self?.restartScreenPreview()
        }
        coordinator.onLiveScreenPreviewFrame = { [weak self] frame in
            guard let self,
                  self.previewFramesAreAllowed,
                  self.coordinator.settings.visibleSources.contains(.screen) else { return }
            self.previewStage.applyLiveFrameAspectRatio(frame.sourceAspectRatio)
            self.previewStage.screenPreview.enqueuePreviewSampleBuffer(frame.sampleBuffer)
        }
        coordinator.onCameraConfigurationChanged = { [weak self] in
            self?.refreshCameraPicker()
        }
        coordinator.onLocalCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.previewFramesAreAllowed,
                  self.coordinator.settings.visibleSources.contains(.camera),
                  !self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.isHidden = false
            self.previewStage.cameraPreview.enqueuePreviewSampleBuffer(sampleBuffer, width: width, height: height)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onLocalCameraThumbnailSampleBuffer = { [weak self] sampleBuffer in
            guard let self,
                  self.previewFramesAreAllowed,
                  self.coordinator.settings.enabledSources.contains(.camera),
                  !self.coordinator.isRemoteCameraSelected else { return }
            self.previewStage.cameraPreview.thumbnailSampler.offer(sampleBuffer)
            guard self.coordinator.state != .idle
                || !self.coordinator.settings.removesCameraBackgroundAfterRecording else { return }
            self.previewStage.cameraPreview.noteCaptureFrame(sampleBuffer)
            self.noteCameraPreviewFrame()
        }
        coordinator.onRemoteCameraPreviewFrame = { [weak self] image in
            guard let self, self.remoteCameraPreviewFramesAreAllowed else { return }
            self.previewStage.cameraPreview.isHidden = false
            let aspectRatio = self.viewModel.applyRemoteCameraPreviewImage(image)
            self.previewStage.cameraPreview.setPreviewImage(image, sourceAspectRatio: aspectRatio)
            self.cameraPreviewDeviceID = self.coordinator.settings.selectedCameraID
        }
        coordinator.onRemoteCameraPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            guard let self, self.remoteCameraPreviewFramesAreAllowed else { return }
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
            guard let self, self.remoteCameraPreviewFramesAreAllowed else { return }
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
        previewStage.fillsCanvasWhenOnlyVideoSource =
            coordinator.settings.enabledSources.intersection([.screen, .camera]).count == 1
        previewStage.sceneLayout = coordinator.settings.sceneLayout
        previewStage.applySettingsAspectRatio(coordinator.currentScreenSourceAspectRatio())
        previewStage.showsRuleOfThirdsOverlay = coordinator.settings.showsRuleOfThirdsOverlay
        previewStage.socialSafeZoneOverlay = coordinator.settings.socialSafeZoneOverlay
        previewStage.canvasBackgroundStyle = coordinator.settings.canvasBackgroundStyle
        previewStage.canvasPadding = coordinator.settings.canvasPadding

        let host = NSHostingView(rootView: MainView(configuration: .init(viewModel: viewModel, mcpServer: mcpServer))
            .environmentObject(configuration.updateController)
            .preferredColorScheme(.dark))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.contentMinSize = Self.minimumWindowContentSize
        window.minSize = Self.minimumWindowContentSize

        viewModel.applyState(coordinator.state)
        if let saved = StudioPagePreference(defaults: .standard).load() {
            viewModel.restoreStudioPage(saved)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startCameraDeviceMonitoring()
            if LocalDevelopmentRuntime.disablesIdleCapture() {
                self.viewModel.syncSettings()
                self.refreshPermissionGate()
                return
            }
            if self.idlePreviewIsAllowed {
                self.startCameraPreview()
                self.refreshStartupState()
                self.startScreenPreview()
            } else {
                self.viewModel.syncSettings()
                self.refreshPermissionGate()
            }
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

    func cancelPendingPermissionRequests() {
        viewModel.cancelPendingPermissionRequests()
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
        cameraPreviewWatchdogTask?.cancel()
        screenPreviewWatchdogTask?.cancel()
        for observer in cameraDeviceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func requestRecordingStart() {
        viewModel.requestRecordingStart()
    }

    func update(for state: RecordingState) {
        let previousState = currentRecordingState
        currentRecordingState = state
        viewModel.applyState(state)
        recordingHUD.update(for: state)
        switch state {
        case .idle:
            refreshPermissionGate()
            if idlePreviewIsAllowed {
                scheduleIdlePreviewRestart(afterNanoseconds: IdlePreviewRestartPolicy.delayNanoseconds(
                    previousState: previousState,
                    newState: state
                ))
            } else {
                suspendIdleCaptureResources()
            }
        case .recording, .paused:
            cancelScheduledIdlePreviewRestart()
            showRecordingCameraPreview()
        case .starting, .finishing:
            cancelScheduledIdlePreviewRestart()
            break
        }
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

    func applyExportFailure(_ message: String?) {
        viewModel.applyExportFailure(message)
    }

    func undoEditor() {
        viewModel.undoEditor()
    }

    func redoEditor() {
        viewModel.redoEditor()
    }

    func updateCaptureStopProgress(_ progress: CaptureStopProgress?) {
        viewModel.captureStopProgress = progress
    }

    func updateRenderProgress(_ progress: Double) {
        viewModel.applyRenderProgress(progress)
    }

    func syncRuleOfThirdsOverlay() {
        viewModel.syncSettings()
    }

    func presentSettings(selecting pane: SettingsPane? = nil) {
        viewModel.showSettings(pane)
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    private func saveStudioPage() {
        StudioPagePreference(defaults: .standard).save(viewModel.savedStudioPage)
    }

    private func showEditorAfterOpeningProject() {
        viewModel.dismissSettings()
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
}
