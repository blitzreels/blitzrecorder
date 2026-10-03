import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

let exportLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "export")

@MainActor
final class RecorderCoordinator {
    let accessController: AccessController
    let permissionGate: PermissionGate
    let studio: RecorderStudioConfiguration
    lazy var remoteCamera = RemoteIPhoneCameraSession(
        readSettings: { [weak self] in
            self?.settings ?? RecordingSettings()
        },
        saveSettings: { [weak self] settings in
            self?.settings = settings
            self?.persistSettings()
        },
        screenAspectRatio: { [weak self] in
            self?.currentScreenSourceAspectRatio() ?? SceneLayout.defaultScreenAspectRatio
        },
        canAttemptPendingImports: { [weak self] in
            self?.state == .idle || self?.state == .finishing
        }
    )
    private let capture: RecorderCaptureRuntime

    var state: RecordingState { capture.state }
    var settings: RecordingSettings {
        get { studio.settings }
        set { studio.settings = newValue }
    }
    var sceneLibrary: SceneLibrary {
        get { studio.sceneLibrary }
        set { studio.sceneLibrary = newValue }
    }
    var lastTake: RecordingTake? { capture.lastTake }
    var screenSourceSelection: ScreenSourceSelection { studio.screenSourceSelection }
    var currentPickedScreenSourceAspectRatio: CGFloat? {
        get { studio.currentPickedScreenSourceAspectRatio }
        set { studio.currentPickedScreenSourceAspectRatio = newValue }
    }
    var isEditingScreenCrop: Bool {
        get { studio.isEditingScreenCrop }
        set { studio.isEditingScreenCrop = newValue }
    }
    var screenContentSelectionRevision: Int { capture.screenContentSelectionRevision }
    var screenWindowGeometryRevision: Int { capture.screenWindowGeometryRevision }
    var isScreenPreviewRunning: Bool { capture.isScreenPreviewRunning }
    var hasActivePickedScreenContent: Bool { capture.hasActivePickedScreenContent }
    var hasActiveScreenSourceSelection: Bool { capture.hasActiveScreenSourceSelection }
    var activePickedScreenContentKind: ScreenSourceBinding.Kind? { capture.activePickedScreenContentKind }

    var onStateChanged: ((RecordingState) -> Void)? {
        didSet { capture.onStateChanged = onStateChanged }
    }
    var onMessage: ((String) -> Void)? {
        didSet { capture.onMessage = onMessage }
    }
    var onSavedRecording: ((SavedRecordingOutput) -> Void)? {
        didSet { capture.onSavedRecording = onSavedRecording }
    }
    var onPostRecordingProject: ((PostRecordingProjectOutput) -> Void)? {
        didSet { capture.onPostRecordingProject = onPostRecordingProject }
    }
    var onRecordingRecovery: ((RecordingRecoveryOutput) -> Void)? {
        didSet { capture.onRecordingRecovery = onRecordingRecovery }
    }
    var onCaptureStopProgress: ((CaptureStopProgress?) -> Void)? {
        didSet { capture.onCaptureStopProgress = onCaptureStopProgress }
    }
    var onRenderProgress: ((Double) -> Void)? {
        didSet { capture.onRenderProgress = onRenderProgress }
    }
    var onExportFailure: ((String?) -> Void)? {
        didSet { capture.onExportFailure = onExportFailure }
    }
    var onRuleOfThirdsOverlayChanged: ((Bool) -> Void)?
    var onSocialSafeZoneOverlayChanged: ((SocialVideoSafeZone) -> Void)?
    var onScreenCaptureConfigurationChanged: (() -> Void)? {
        didSet { capture.onScreenCaptureConfigurationChanged = onScreenCaptureConfigurationChanged }
    }
    var onCameraConfigurationChanged: (() -> Void)? {
        didSet { capture.onCameraConfigurationChanged = onCameraConfigurationChanged }
    }
    var onRequestForeground: (() -> Void)? {
        didSet { capture.onRequestForeground = onRequestForeground }
    }
    var onLiveScreenPreviewFrame: ScreenPreviewer.FrameHandler? {
        didSet { capture.onLiveScreenPreviewFrame = onLiveScreenPreviewFrame }
    }
    var onLocalCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)? {
        didSet { capture.onLocalCameraPreviewSampleBuffer = onLocalCameraPreviewSampleBuffer }
    }
    var onLocalCameraThumbnailSampleBuffer: CameraRecorder.ThumbnailHandler? {
        didSet { capture.cameraRecorder.setThumbnailHandler(onLocalCameraThumbnailSampleBuffer) }
    }
    var onRemoteCameraPreviewFrame: ((CGImage) -> Void)?
    var onRemoteCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onRemoteCameraPreviewReset: ((String) -> Void)?
    var onRemoteCameraPairingCodeRequested: ((String) -> String?)?
    var onAudioLevel: ((CaptureSource, Float) -> Void)? {
        didSet { capture.onAudioLevel = onAudioLevel }
    }

    init(accessController: AccessController, defaults: UserDefaults? = nil) {
        self.accessController = accessController
        permissionGate = PermissionGate()
        let recents = ScreenSourcePickerRecents(defaults: defaults ?? .standard)
        studio = RecorderStudioConfiguration(defaults: defaults)
        capture = RecorderCaptureRuntime(studio: studio, permissionGate: permissionGate, recents: recents)
        bindStudioCallbacks()
        recents.record(settings.screenSourceBinding)
        capture.remoteCamera = remoteCamera
        remoteCamera.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        remoteCamera.onCameraConfigurationChanged = { [weak self] in
            self?.capture.refitCameraInsetToCurrentCamera()
            self?.onCameraConfigurationChanged?()
        }
        remoteCamera.onPreviewFrame = { [weak self] image in
            self?.onRemoteCameraPreviewFrame?(image)
        }
        remoteCamera.onPreviewSampleBuffer = { [weak self] sampleBuffer, width, height in
            self?.onRemoteCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
        remoteCamera.onPreviewReset = { [weak self] message in
            self?.onRemoteCameraPreviewReset?(message)
        }
        remoteCamera.onPairingCodeRequested = { [weak self] deviceName in
            self?.onRemoteCameraPairingCodeRequested?(deviceName)
        }
        capture.bindCaptureEngine()
        if RemoteCameraProviderID.isRemote(settings.selectedCameraID) {
            startRemoteCameraDiscoveryIfNeeded()
        }
        if capture.refitCameraInsetFrameForCurrentSource() {
            persistSettings()
        }
    }

    func persistSettings(saveSceneSnapshot: Bool = true) {
        studio.persist(saveSceneSnapshot: saveSceneSnapshot)
    }

    func cameraPreviewLayer() async throws -> AVCaptureVideoPreviewLayer {
        try await capture.cameraPreviewLayer()
    }

    func prewarmLocalCameraPreviewIfAuthorized() {
        capture.prewarmLocalCameraPreviewIfAuthorized()
    }

    func startScreenPreview(frameHandler: @escaping ScreenPreviewer.FrameHandler) async throws {
        try await capture.startScreenPreview(frameHandler: frameHandler)
    }

    func stopScreenPreview() async { await capture.stopScreenPreview() }
    func stopCameraPreview() async { await capture.stopCameraPreview() }
    func shutdown() async { await capture.shutdown() }
    func suspendIdleCaptureResources() async { await capture.suspendIdleCaptureResources() }
    func resumeIdleAudioLevelMonitoring() async { await capture.resumeIdleAudioLevelMonitoring() }

    func startCameraCutoutPreview(frameHandler: @escaping CameraCutoutPreviewer.FrameHandler) async throws {
        try await capture.startCameraCutoutPreview(frameHandler: frameHandler)
    }

    func previewSceneLayout(_ sceneLayout: SceneLayout) {
        capture.previewSceneLayout(sceneLayout)
    }

    func setSource(_ source: CaptureSource, enabled: Bool) { capture.setSource(source, enabled: enabled) }
    func uniqueOutputURL(_ url: URL) -> URL { capture.uniqueOutputURL(url) }
    func setMicrophone(id: String?) { capture.setMicrophone(id: id) }
    func hasScreenCaptureAccess() -> Bool { capture.hasScreenCaptureAccess() }
    func recordingReadiness() -> RecordingReadiness { capture.recordingReadiness() }
    func setLocalCameraRuntimeState(_ state: LocalCameraRuntimeState) {
        capture.setLocalCameraRuntimeState(state)
    }
    func requestPermissionsForEnabledSources() async { await capture.requestPermissionsForEnabledSources() }
    func availableCameras() -> [SourceOption] { capture.availableCameras() }
    func availableMicrophones() -> [SourceOption] { capture.availableMicrophones() }
    func selectedMicrophoneName() -> String { capture.selectedMicrophoneName() }
    func start() { capture.start() }
    func pause() { capture.pause() }
    func resume() { capture.resume() }
    func stop() { capture.stop() }
    func refreshAudioLevelMonitoring() { capture.refreshAudioLevelMonitoring() }
    func mergeLastTake() { capture.mergeLastTake() }
    func exportProject(_ request: ProjectExportRequest) { capture.exportProject(request) }
    func exportProjectForAgent(_ request: ProjectExportRequest) async throws -> SavedRecordingOutput {
        try await capture.exportProjectForAgent(request)
    }
    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        correction: RecordingProjectSceneCorrection
    ) throws -> RecordingProject {
        try capture.updateProjectScene(at: projectURL, eventIndex: eventIndex, correction: correction)
    }
    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        mutate: (inout RecordingScene) -> Void
    ) throws -> RecordingProject {
        try capture.updateProjectScene(at: projectURL, eventIndex: eventIndex, mutate: mutate)
    }
    func insertProjectSceneEvent(at projectURL: URL, time: Double) throws -> RecordingProject {
        try capture.insertProjectSceneEvent(at: projectURL, time: time)
    }
    func removeProjectSceneEvent(at projectURL: URL, eventIndex: Int) throws -> RecordingProject {
        try capture.removeProjectSceneEvent(at: projectURL, eventIndex: eventIndex)
    }
    func restoreProjectSceneTimeline(
        _ request: RecordingProjectSceneRestoreRequest
    ) throws -> RecordingProject {
        try capture.restoreProjectSceneTimeline(request)
    }
    func updateProjectEditorState(
        _ request: RecordingProjectEditorStateUpdateRequest
    ) throws -> RecordingProject {
        try capture.updateProjectEditorState(request)
    }
    func zoomIn() { capture.zoomIn() }
    func zoomOut() { capture.zoomOut() }
    func resetZoom() { capture.resetZoom() }
    func openOutputFolder() { capture.openOutputFolder() }

    func setScreenSource(_ binding: ScreenSourceBinding, autoFitWindowZoom: CGFloat? = nil) {
        capture.setScreenSource(binding, autoFitWindowZoom: autoFitWindowZoom)
    }
    func targetWindowInfo() throws -> TargetWindowInfo { try capture.targetWindowInfo() }
    func fitFrontWindowForShorts() { capture.fitFrontWindowForShorts() }
    func fitScreenItemToFrontWindow() { capture.fitScreenItemToFrontWindow() }
    func fitFrontWindowForShorts(zoom: CGFloat) { capture.fitFrontWindowForShorts(zoom: zoom) }
    func fitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        capture.fitScreenSourceWindow(binding, zoom: zoom)
    }
    func fitPickedScreenWindowToSlot(zoom: CGFloat) { capture.fitPickedScreenWindowToSlot(zoom: zoom) }
    func cancelPendingScreenWindowFits() { capture.cancelPendingScreenWindowFits() }
    func zoomScreenSourceContent(_ direction: AppContentZoomDirection) {
        capture.zoomScreenSourceContent(direction)
    }
    func resizeTargetWindow(widthDelta: CGFloat, heightDelta: CGFloat) {
        capture.resizeTargetWindow(widthDelta: widthDelta, heightDelta: heightDelta)
    }
    func setTargetWindowSize(width: CGFloat, height: CGFloat) {
        capture.setTargetWindowSize(width: width, height: height)
    }
    func currentScreenSourceAspectRatio() -> CGFloat { capture.currentScreenSourceAspectRatio() }
    func currentCameraSourceAspectRatio() -> CGFloat { capture.currentCameraSourceAspectRatio() }
    func selectScreenCrop() async throws { try await capture.selectScreenCrop() }
    func availableDisplays() async -> [SourceOption] { await capture.availableDisplays() }
    func availableScreenSources() async -> [ScreenSourceOption] { await capture.availableScreenSources() }
    func screenSourceThumbnail(_ binding: ScreenSourceBinding) async -> NSImage? {
        await capture.screenSourceThumbnail(binding)
    }
    func pickScreenContent() async throws { try await capture.pickScreenContent() }
    func pickScreenSource() async throws { try await capture.pickScreenSource() }
    func pickFullScreenSource() async throws { try await capture.pickFullScreenSource() }

    static func readableScreenApplicationName(_ name: String?) -> String? {
        ScreenSourceCatalog.readableApplicationName(name)
    }
    static func screenApplicationKey(
        bundleIdentifier: String?,
        processID: pid_t?,
        applicationName: String?
    ) -> String {
        ScreenSourceCatalog.applicationKey(
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            applicationName: applicationName
        )
    }
    static func isIgnoredScreenApplication(
        bundleIdentifier: String?,
        applicationName: String?
    ) -> Bool {
        ScreenSourceCatalog.isIgnoredApplication(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName
        )
    }
    static func isIgnoredScreenWindow(
        bundleIdentifier: String?,
        applicationName: String?,
        title: String?
    ) -> Bool {
        ScreenSourceCatalog.isIgnoredWindow(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: title
        )
    }
    static func readableScreenWindowTitle(_ title: String?) -> String? {
        ScreenSourceCatalog.readableWindowTitle(title)
    }

    func bindStudioCallbacks() {
        studio.recordingState = { [weak self] in self?.state ?? .idle }
        studio.screenAspectRatio = { [weak self] in
            self?.currentScreenSourceAspectRatio() ?? SceneLayout.defaultScreenAspectRatio
        }
        studio.cameraAspectRatio = { [weak self] in
            self?.currentCameraSourceAspectRatio() ?? SceneLayout.cameraAspectRatio
        }
        studio.refitCameraInset = { [weak self] in
            self?.capture.refitCameraInsetFrameForCurrentSource() ?? false
        }
        studio.onMessage = { [weak self] message in self?.onMessage?(message) }
        studio.onScreenCaptureConfigurationChanged = { [weak self] in
            self?.onScreenCaptureConfigurationChanged?()
        }
        studio.onCameraConfigurationChanged = { [weak self] in
            self?.onCameraConfigurationChanged?()
        }
        studio.onRuleOfThirdsOverlayChanged = { [weak self] visible in
            self?.onRuleOfThirdsOverlayChanged?(visible)
        }
        studio.onSocialSafeZoneOverlayChanged = { [weak self] overlay in
            self?.onSocialSafeZoneOverlayChanged?(overlay)
        }
        studio.updateRecordingScene = { [weak self] transition in
            self?.capture.updateRecordingSceneIfNeeded(transition: transition)
        }
        studio.refreshAudio = { [weak self] in self?.capture.refreshAudioLevelMonitoring() }
        studio.autoFitSelectedScreenWindow = { [weak self] in
            self?.capture.autoFitSelectedScreenWindowToSceneSlot()
        }
    }
}
