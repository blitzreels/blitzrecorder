import CoreGraphics
import Foundation

@MainActor
final class RecorderStudioConfiguration {
    var settings: RecordingSettings
    var sceneLibrary: SceneLibrary
    let screenSourceSelection = ScreenSourceSelection()
    var currentPickedScreenSourceAspectRatio: CGFloat?
    var isEditingScreenCrop = false

    private let defaults: UserDefaults?

    var recordingState: () -> RecordingState = { .idle }
    var screenAspectRatio: () -> CGFloat = { SceneLayout.defaultScreenAspectRatio }
    var cameraAspectRatio: () -> CGFloat = { SceneLayout.cameraAspectRatio }
    var refitCameraInset: () -> Bool = { false }
    var onMessage: ((String) -> Void)?
    var onScreenCaptureConfigurationChanged: (() -> Void)?
    var onCameraConfigurationChanged: (() -> Void)?
    var onRuleOfThirdsOverlayChanged: ((Bool) -> Void)?
    var onSocialSafeZoneOverlayChanged: ((SocialVideoSafeZone) -> Void)?
    var updateRecordingScene: ((RecordingSceneTransition) -> Void)?
    var refreshAudio: (() -> Void)?
    var autoFitSelectedScreenWindow: (() -> Void)?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        settings = RecordingSettingsStore.load(defaults: defaults)
        sceneLibrary = SceneLibraryStore.load(defaults: defaults, currentSettings: settings)
        if let selectedScene = sceneLibrary.selectedScene(layout: settings.layout) {
            applySceneSnapshot(selectedScene.snapshot)
        }
        if let next = RecordingSceneMutation.clearingIncompatibleScreenCrop(settings) {
            settings = next
            persist()
        }
    }

    var state: RecordingState { recordingState() }

    var allowsSceneChanges: Bool {
        let state = state
        return state == .idle || state == .recording || state == .paused
    }

    func persist(saveSceneSnapshot: Bool = true) {
        if saveSceneSnapshot {
            saveCurrentSceneSnapshotIfNeeded()
        }
        RecordingSettingsStore.save(settings, defaults: defaults)
    }

    func saveCurrentSceneSnapshotIfNeeded() {
        guard state == .idle else { return }
        sceneLibrary.updateSelectedScene(
            layout: settings.layout,
            snapshot: currentRecordingSceneSnapshot()
        )
        saveSceneLibrary()
    }

    func saveSceneLibrary() {
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
    }

    func applySceneSnapshot(_ snapshot: RecordingSceneSnapshot) {
        settings = snapshot.applying(to: settings)
        if snapshot.restoresConcreteScreenSource {
            settings = screenSourceSelection.restore(
                ScreenSourceSelection.RestoreRequest(
                    snapshot: ScreenSourceSelectionSnapshot(
                        usesPickedContent: snapshot.usesPickedScreenContent,
                        binding: snapshot.screenSourceBinding,
                        selectedDisplayID: snapshot.selectedDisplayID,
                        crop: snapshot.screenCrop,
                        pickedContentSelectionID: snapshot.pickedScreenContentSelectionID
                    ),
                    settings: settings
                )
            )
            settings.screenSourceAspectRatio = snapshot.screenSourceAspectRatio
        }
        _ = refitCameraInset()
    }

    func currentScreenSourceSelection() -> ScreenSourceSelectionSnapshot {
        screenSourceSelection.snapshot(from: settings)
    }

    func currentRecordingSceneSnapshot() -> RecordingSceneSnapshot {
        var snapshot = RecordingSceneSnapshot(settings: settings)
        snapshot.pickedScreenContentSelectionID = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentSelectionID
            : nil
        return snapshot
    }

    func restoreScreenSourceSelection(_ selection: ScreenSourceSelectionSnapshot) {
        settings = screenSourceSelection.restore(
            ScreenSourceSelection.RestoreRequest(snapshot: selection, settings: settings)
        )
        if let next = RecordingSceneMutation.clearingIncompatibleScreenCrop(settings) {
            settings = next
        }
    }

    func recomputeSelectedPresetLayoutForCurrentSource() {
        guard let preset = settings.selectedScenePreset,
              preset.supports(settings.layout) else { return }
        settings.sceneLayout = SceneLayout.presetLayout(
            preset,
            for: settings.layout,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        ).withCameraSide(settings.sceneLayout.cameraSide)
    }

    func applyFittedScreenWindowArrangement(
        _ arrangement: ShortsWindowArrangement,
        shouldUpdateCapture: Bool
    ) {
        if let fittedZoom = arrangement.fittedZoom {
            settings.screenWindowZoom = ScreenSourceZoomGeometry.clamped(fittedZoom)
        }
        if arrangement.frame.width > 0, arrangement.frame.height > 0 {
            let aspectRatio = arrangement.frame.width / arrangement.frame.height
            settings.screenSourceAspectRatio = aspectRatio
            if aspectRatio > 0 {
                currentPickedScreenSourceAspectRatio = aspectRatio
            }
            persist()
        }
        updateRecordingScene?(.cut)
        if shouldUpdateCapture {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func setOutputResolution(_ outputResolution: OutputResolution) {
        settings.outputResolution = outputResolution
        persist()
    }

    func setOutputVideoFormat(_ outputVideoFormat: OutputVideoFormat) {
        settings.outputVideoFormat = outputVideoFormat
        persist()
    }

    func setFramesPerSecond(_ framesPerSecond: Int) {
        guard RecordingSettings.supportedFrameRates.contains(framesPerSecond) else { return }
        settings.framesPerSecond = framesPerSecond
        persist()
        onCameraConfigurationChanged?()
    }

    func setCustomVideoBitrate(_ bitrate: Int?) {
        if let bitrate {
            settings.customVideoBitrate = min(
                RecordingSettings.maxCustomVideoBitrate,
                max(RecordingSettings.minCustomVideoBitrate, bitrate)
            )
        } else {
            settings.customVideoBitrate = nil
        }
        persist()
    }

    func setAudioQuality(_ audioQuality: AudioQuality) {
        settings.audioQuality = audioQuality
        persist()
    }

    func setSourceAudioFormat(_ sourceAudioFormat: SourceAudioFormat) {
        settings.sourceAudioFormat = sourceAudioFormat
        persist()
    }

    func setMicrophoneGain(_ microphoneGain: Double) {
        settings.microphoneGain = CaptureValueClamps.gain(microphoneGain)
        persist()
    }

    func setSystemAudioGain(_ systemAudioGain: Double) {
        settings.systemAudioGain = CaptureValueClamps.gain(systemAudioGain)
        persist()
    }

    func setCameraBackgroundRemovalAfterRecording(_ enabled: Bool) {
        let wasEnabled = settings.removesCameraBackgroundAfterRecording
        settings.removesCameraBackgroundAfterRecording = enabled
        if enabled, !wasEnabled {
            settings.cameraCropAmount = .zero
            settings.cameraCropPosition = .zero
            if settings.enabledSources.contains(.screen) {
                settings.selectedScenePreset = nil
                settings.screenCrop = nil
                settings.sceneLayout.screenFrame = SceneLayerResizing.clamped(
                    SceneLayout.canvasFillingFrame(
                        sourceAspectRatio: screenAspectRatio(),
                        canvasAspectRatio: settings.layout.aspectRatio
                    )
                )
                onScreenCaptureConfigurationChanged?()
            }
        }
        persist()
        onCameraConfigurationChanged?()
    }

    func setSourceFilesSaved(_: Bool) {
        settings.savesSourceFiles = true
        persist()
    }

    func setRuleOfThirdsOverlayVisible(_ visible: Bool) {
        settings.showsRuleOfThirdsOverlay = visible
        persist()
        onRuleOfThirdsOverlayChanged?(visible)
    }

    func setSocialSafeZoneOverlay(_ overlay: SocialVideoSafeZone) {
        settings.socialSafeZoneOverlay = overlay
        persist()
        onSocialSafeZoneOverlayChanged?(overlay)
    }

    func setCursorIncluded(_ included: Bool) {
        settings.includeCursor = included
        persist()
    }

    func setSourceVisibilityDuringLiveCompositor(_ source: CaptureSource, enabled: Bool) {
        applySourceVisibility(source, enabled: enabled)
    }

    func addSource(_ source: CaptureSource) {
        guard state == .idle else {
            onMessage?("Capture sources are locked while recording.")
            return
        }
        settings.enabledSources.insert(source)
        settings.hiddenSources.remove(source)
        persist()
        refreshAudio?()
        notifySource(source)
    }

    func removeSource(_ source: CaptureSource) {
        guard state == .idle else {
            onMessage?("Capture sources are locked while recording.")
            return
        }
        settings.enabledSources.remove(source)
        settings.hiddenSources.remove(source)
        persist()
        refreshAudio?()
        notifySource(source)
    }

    func setOutputDirectory(_ url: URL) {
        if settings.projectLibrary == nil { settings.projectLibrary = settings.sourceStorage }
        settings.outputDirectory = url
        settings.outputDirectoryBookmarkData = RecordingSettingsStore.bookmarkData(for: url)
        persist()
    }

    func setSourceDirectory(_ url: URL) {
        guard state == .idle else { return }
        let libraries = settings.projectLibraries
        let selectedRoot = url.standardizedFileURL.resolvingSymlinksInPath()
        settings.projectLibrary = RecordingStorageLocation(url: url, bookmarkData: RecordingSettingsStore.bookmarkData(for: url))
        settings.additionalProjectLibraries = libraries.filter {
            $0.url.standardizedFileURL.resolvingSymlinksInPath() != selectedRoot
        }
        persist(saveSceneSnapshot: false)
    }

    func setDisplay(id: String?) {
        guard state == .idle else {
            onMessage?("Use the recording Screen control to switch sources mid-recording.")
            return
        }
        settings = screenSourceSelection.selectDisplay(
            ScreenSourceSelection.DisplayRequest(id: id, settings: settings)
        )
        currentPickedScreenSourceAspectRatio = nil
        persist()
        refreshAudio?()
        onScreenCaptureConfigurationChanged?()
    }

    func applyIdleScreenSource(_ binding: ScreenSourceBinding) {
        settings = screenSourceSelection.selectBinding(
            ScreenSourceSelection.BindingRequest(binding: binding, settings: settings)
        )
        currentPickedScreenSourceAspectRatio = nil
        settings.enabledSources.insert(.screen)
        settings.hiddenSources.remove(.screen)
        if state == .idle {
            settings.screenContentMode = .fit
        }
        persist()
        updateRecordingScene?(.cut)
        refreshAudio?()
        onScreenCaptureConfigurationChanged?()
    }

    func applyIdleMicrophone(id: String?) {
        settings.selectedMicrophoneID = id
        persist()
        refreshAudio?()
    }

    private func applySourceVisibility(_ source: CaptureSource, enabled: Bool) {
        if enabled {
            settings.enabledSources.insert(source)
            settings.hiddenSources.remove(source)
        } else if source == .screen || source == .camera {
            settings.enabledSources.insert(source)
            settings.hiddenSources.insert(source)
        } else {
            settings.enabledSources.remove(source)
            settings.hiddenSources.remove(source)
        }
        persist()
        updateRecordingScene?(.cut)
        refreshAudio?()
        notifySource(source)
    }

    private func notifySource(_ source: CaptureSource) {
        if source == .camera {
            onCameraConfigurationChanged?()
        } else if source == .screen {
            onScreenCaptureConfigurationChanged?()
        }
    }
}
