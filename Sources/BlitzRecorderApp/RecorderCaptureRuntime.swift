import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

@MainActor
final class RecorderCaptureRuntime {
    let studio: RecorderStudioConfiguration
    let permissionGate: PermissionGate
    var remoteCamera: RemoteIPhoneCameraSession!

    let screenRecorder = ScreenRecorder()
    let screenPreviewer = ScreenPreviewer()
    let screenThumbnailProvider = ScreenSourceThumbnailProvider()
    let screenContentPicker = ScreenContentPicker()
    let screenSourcePickerRecents: ScreenSourcePickerRecents
    let screenCropPicker = ScreenCropPicker()
    let cameraRecorder = CameraRecorder()
    let cameraCutoutPreviewer = CameraCutoutPreviewer()
    let audioRecorder = AudioRecorder()
    let systemAudioRecorder = SystemAudioRecorder()
    let takeRecording = TakeRecordingRuntime()
    let microphoneLevelMonitor = MicrophoneLevelMonitor()
    let systemAudioLevelMonitor = SystemAudioLevelMonitor()
    let takeFileStore = TakeFileStore()
    let captureDeviceMonitor = CaptureDeviceMonitor()
    let screenReconfiguration = ActiveScreenCaptureReconfiguration()
    let recordingSession = RecordingSession()
    var idleCaptureResourcesEnabled = true
    lazy var takeFinalizer: TakeFinalizer = {
        let finalizer = TakeFinalizer()
        finalizer.onMessage = { [weak self] message in
            self?.onMessage?(message)
        }
        finalizer.onRenderProgress = { [weak self] progress in
            self?.onRenderProgress?(progress)
        }
        return finalizer
    }()

    var settings: RecordingSettings {
        get { studio.settings }
        set { studio.settings = newValue }
    }
    var state: RecordingState { recordingSession.state }
    var lastTake: RecordingTake? { recordingSession.lastTake }
    var screenSourceSelection: ScreenSourceSelection { studio.screenSourceSelection }
    var currentPickedScreenSourceAspectRatio: CGFloat? {
        get { studio.currentPickedScreenSourceAspectRatio }
        set { studio.currentPickedScreenSourceAspectRatio = newValue }
    }
    var isEditingScreenCrop: Bool {
        get { studio.isEditingScreenCrop }
        set { studio.isEditingScreenCrop = newValue }
    }
    var isRemoteCameraSelected: Bool {
        remoteCamera.isRemoteCameraSelected()
    }

    var screenContentSelectionRevision = 0
    var screenWindowGeometryRevision = 0
    var screenWindowFitRevision = 0
    var committedRecordingSettings: RecordingSettings?
    var localCameraRuntimeState: LocalCameraRuntimeState = .unchecked
    var activeMicrophoneDeviceID: String?
    var activeLocalCameraDeviceID: String?
    var activeCaptureWarnings: [String] = []

    struct ScreenSourceActionContext: Equatable {
        let screenWindowFitRevision: Int
        let screenContentSelectionRevision: Int
        let screenSourceBinding: ScreenSourceBinding?
        let usesPickedScreenContent: Bool
    }

    var onStateChanged: ((RecordingState) -> Void)? {
        didSet { recordingSession.onStateChanged = onStateChanged }
    }
    var onMessage: ((String) -> Void)?
    var onSavedRecording: ((SavedRecordingOutput) -> Void)?
    var onPostRecordingProject: ((PostRecordingProjectOutput) -> Void)?
    var onRecordingRecovery: ((RecordingRecoveryOutput) -> Void)?
    var onRenderProgress: ((Double) -> Void)?
    var onExportFailure: ((String?) -> Void)?
    var onScreenCaptureConfigurationChanged: (() -> Void)?
    var onCameraConfigurationChanged: (() -> Void)?
    var onRequestForeground: (() -> Void)?
    var onLiveScreenPreviewFrame: ScreenPreviewer.FrameHandler?
    var onLocalCameraPreviewSampleBuffer: ((CMSampleBuffer, Int, Int) -> Void)?
    var onAudioLevel: ((CaptureSource, Float) -> Void)? {
        didSet {
            audioRecorder.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.microphone, level)
            }
            systemAudioRecorder.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.systemAudio, level)
            }
            microphoneLevelMonitor.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.microphone, level)
            }
            systemAudioLevelMonitor.levelHandler = { [weak self] level in
                self?.onAudioLevel?(.systemAudio, level)
            }
        }
    }

    init(studio: RecorderStudioConfiguration, permissionGate: PermissionGate, recents: ScreenSourcePickerRecents) {
        self.studio = studio
        self.permissionGate = permissionGate
        screenSourcePickerRecents = recents
    }

    func persistSettings(saveSceneSnapshot: Bool = true) {
        studio.persist(saveSceneSnapshot: saveSceneSnapshot)
    }

    func requireRemoteCameraConnection() async throws {
        try await remoteCamera.requireConnection()
    }

    func remoteCameraConnectionBlocker() -> PermissionBlocker? {
        remoteCamera.connectionBlocker()
    }

    func remoteCameraOptions() -> [SourceOption] {
        remoteCamera.cameraOptions()
    }

    func sceneChangeIsAllowed() -> Bool {
        guard studio.allowsSceneChanges else {
            onMessage?("Scene layout is locked while saving.")
            return false
        }
        return true
    }

    func applyFittedScreenWindowArrangement(
        _ arrangement: ShortsWindowArrangement,
        shouldUpdateCapture: Bool
    ) {
        screenWindowGeometryRevision += 1
        studio.applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: shouldUpdateCapture)
    }

    func screenSettingsWithoutCrop() -> RecordingSettings {
        studio.screenSettingsWithoutCrop()
    }

    func clearCustomScreenCrop() {
        studio.clearCustomScreenCrop()
    }

    @discardableResult
    func refitCameraInsetFrameForCurrentSource() -> Bool {
        guard let sourceAspectRatio = knownCameraSourceAspectRatio() else { return false }
        return studio.refitCameraInsetFrame(sourceAspectRatio: sourceAspectRatio)
    }

    func cameraPreviewLayer() async throws -> AVCaptureVideoPreviewLayer {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        guard await permissionGate.requestCameraAccess() else {
            throw RecorderError.noCamera
        }
        return try await cameraRecorder.makePreviewLayer(settings: settings)
    }

    func prewarmLocalCameraPreviewIfAuthorized() {
        guard permissionGate.cameraAuthorizationStatus == .authorized,
              settings.enabledSources.contains(.camera),
              !settings.hiddenSources.contains(.camera),
              !settings.removesCameraBackgroundAfterRecording,
              !isRemoteCameraSelected else { return }
        cameraRecorder.prewarmPreview(settings: settings)
    }

    func startScreenPreview(frameHandler: @escaping ScreenPreviewer.FrameHandler) async throws {
        guard state != .idle || idleCaptureResourcesEnabled else { return }
        var previewSettings = settings
        if isEditingScreenCrop {
            previewSettings.screenCrop = nil
        }
        let sourceBinding = previewSettings.screenSourceBinding
        let resolvedBinding = try await screenPreviewer.start(
            settings: previewSettings,
            filter: pickedScreenFilter(for: previewSettings),
            frameHandler: { [weak self] frame in
                self?.studio.noteScreenSourceAspectRatio(frame.sourceAspectRatio)
                frameHandler(frame)
            }
        )
        if !previewSettings.usesPickedScreenContent,
           sourceBinding?.kind == .application,
           settings.screenSourceBinding == sourceBinding,
           let resolvedBinding, resolvedBinding.kind == .window {
            settings.screenSourceBinding = resolvedBinding
            persistSettings()
        }
    }

    var isScreenPreviewRunning: Bool {
        screenPreviewer.isRunning
    }

    func stopScreenPreview() async {
        try? await screenPreviewer.stop()
    }

    func stopCameraPreview() async {
        await cameraRecorder.stopSession()
        await cameraCutoutPreviewer.stop()
    }

    func shutdown() async {
        captureDeviceMonitor.stop()
        if state == .recording || state == .paused {
            stop()
        }
        for _ in 0..<600 {
            if state == .idle { break }
            if state == .recording || state == .paused {
                stop()
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if state != .idle {
            await takeRecording.stopAnyActiveRecording()
        }
        idleCaptureResourcesEnabled = false
        await stopScreenPreview()
        await stopCameraPreview()
        await stopAudioLevelMonitoring()
        remoteCamera.shutdown()
        clearActiveCaptureDevices()
    }

    func suspendIdleCaptureResources() async {
        idleCaptureResourcesEnabled = false
        await stopScreenPreview()
        await stopCameraPreview()
        await stopAudioLevelMonitoring()
    }

    func resumeIdleAudioLevelMonitoring() async {
        guard state == .idle else { return }
        idleCaptureResourcesEnabled = true
        await configureAudioLevelMonitoring()
    }

    func startCameraCutoutPreview(frameHandler: @escaping CameraCutoutPreviewer.FrameHandler) async throws {
        if isRemoteCameraSelected {
            throw RecorderError.remoteCameraPreviewUnavailable
        }
        guard await permissionGate.requestCameraAccess() else {
            throw RecorderError.noCamera
        }
        await cameraRecorder.stopSession()
        try await cameraCutoutPreviewer.start(settings: settings, frameHandler: frameHandler)
    }

    func previewSceneLayout(_ sceneLayout: SceneLayout) {
        guard sceneChangeIsAllowed(), state == .recording || state == .paused else { return }
        var previewSettings = settings
        previewSettings.selectedScenePreset = nil
        previewSettings.sceneLayout.screenFrame = SceneLayerResizing.clamped(sceneLayout.screenFrame)
        previewSettings.sceneLayout.cameraFrame = SceneLayerResizing.clamped(sceneLayout.cameraFrame)
        previewSettings.sceneLayout.layerOrder = sceneLayout.layerOrder
        let screenFilter = previewSettings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentFilter
            : nil
        takeRecording.updateScene(
            RecordingScene.live(settings: previewSettings, pickedFilter: screenFilter),
            transition: .cut
        )
    }

    func bindCaptureEngine() {
        screenPreviewer.failureHandler = { [weak self] error in
            guard let self,
                  self.state == .idle,
                  self.idleCaptureResourcesEnabled,
                  self.settings.visibleSources.contains(.screen) else { return }
            self.onMessage?("Screen preview interrupted. Restarting: \(error.localizedDescription)")
            self.onScreenCaptureConfigurationChanged?()
        }
        screenRecorder.failureHandler = { [weak self] error in
            self?.handleActiveCaptureFailure(ActiveCaptureFailure(source: .screen, error: error))
        }
        systemAudioRecorder.failureHandler = { [weak self] error in
            self?.handleActiveCaptureFailure(ActiveCaptureFailure(source: .systemAudio, error: error))
        }
        cameraRecorder.failureHandler = { [weak self] error in
            self?.handleActiveCaptureFailure(ActiveCaptureFailure(source: .camera, error: error))
        }
        audioRecorder.failureHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleActiveMicrophoneCaptureFailure(error)
            }
        }
        audioRecorder.syncWarningHandler = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.onMessage?(message)
            }
        }
        takeRecording.setCaptureFailureHandler { [weak self] failure in
            self?.handleActiveCaptureFailure(failure)
        }
        startCaptureDeviceMonitoring()
        takeRecording.setLiveCompositorCameraPreviewHandler { [weak self] sampleBuffer, width, height in
            guard let self,
                  self.state == .starting || self.state == .recording || self.state == .paused,
                  self.settings.visibleSources.contains(.camera) else {
                return
            }
            self.onLocalCameraPreviewSampleBuffer?(sampleBuffer, width, height)
        }
        takeRecording.setLiveCompositorScreenPreviewHandler { [weak self] frame in
            guard let self,
                  self.state == .starting || self.state == .recording || self.state == .paused,
                  self.settings.visibleSources.contains(.screen) else {
                return
            }
            self.studio.noteScreenSourceAspectRatio(frame.sourceAspectRatio)
            self.onLiveScreenPreviewFrame?(frame)
        }
    }
}
