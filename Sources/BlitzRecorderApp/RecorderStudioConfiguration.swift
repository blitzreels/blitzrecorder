import CoreGraphics
import CoreMedia
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
        )
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

    func scenesForCurrentLayout() -> [RecordingSceneDefinition] {
        sceneLibrary.scenes(for: settings.layout)
    }

    func scenes(for layout: CaptureLayout) -> [RecordingSceneDefinition] {
        sceneLibrary.scenes(for: layout)
    }

    func layout(ofSceneID id: UUID) -> CaptureLayout? {
        sceneLibrary.layout(ofSceneID: id)
    }

    func selectedSceneIDForCurrentLayout() -> UUID? {
        sceneLibrary.selectedSceneIDsByLayout[settings.layout]
    }

    func selectedSceneName() -> String {
        sceneLibrary.selectedScene(layout: settings.layout)?.name ?? "Scene"
    }

    func selectScene(id: UUID) {
        guard allowsSceneChanges else {
            onMessage?("Scenes are locked while saving.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        guard let scene = sceneLibrary.selectScene(id: id, layout: settings.layout) else { return }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        let screenSelection = currentScreenSourceSelection()
        let screenAspectRatio = settings.screenSourceAspectRatio
        applySceneSnapshot(scene.snapshot)
        restoreScreenSourceSelection(screenSelection)
        settings.screenSourceAspectRatio = screenAspectRatio
        persist(saveSceneSnapshot: false)
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if state == .idle {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    func createSceneFromCurrentSettings(named name: String? = nil) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        let snapshot = currentRecordingSceneSnapshot()
        let scene = sceneLibrary.createScene(
            layout: settings.layout,
            name: name ?? RecordingSceneDefinition.defaultName(for: settings),
            snapshot: snapshot
        )
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        applySceneSnapshot(scene.snapshot)
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func duplicateSelectedScene() {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        saveCurrentSceneSnapshotIfNeeded()
        guard let selectedSceneID = sceneLibrary.selectedSceneIDsByLayout[settings.layout],
              let scene = sceneLibrary.duplicateScene(id: selectedSceneID, layout: settings.layout) else {
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        applySceneSnapshot(scene.snapshot)
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func renameScene(id: UUID, to name: String) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        guard sceneLibrary.renameScene(id: id, layout: settings.layout, name: name) else {
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
    }

    func deleteScene(id: UUID) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        guard sceneLibrary.deleteScene(id: id, layout: settings.layout) else {
            onMessage?("Keep at least one scene in this canvas format.")
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        if let selectedScene = sceneLibrary.selectedScene(layout: settings.layout) {
            applySceneSnapshot(selectedScene.snapshot)
            persist(saveSceneSnapshot: false)
            onScreenCaptureConfigurationChanged?()
            onCameraConfigurationChanged?()
        }
    }

    func moveScene(id: UUID, to index: Int) {
        guard state == .idle else {
            onMessage?("Scene library editing is locked while recording.")
            return
        }
        guard sceneLibrary.moveScene(id: id, layout: settings.layout, to: index) else {
            return
        }
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
    }

    func setLayout(_ layout: CaptureLayout) {
        guard state == .idle else {
            onMessage?("Output aspect ratio is locked while recording.")
            return
        }
        guard settings.layout != layout else {
            if let next = RecordingSceneMutation.clearingIncompatibleScreenCrop(settings) {
                settings = next
                persist()
                onScreenCaptureConfigurationChanged?()
            }
            return
        }
        let preservedScreenSource = currentScreenSourceSelection()
        saveCurrentSceneSnapshotIfNeeded()
        settings.layout = layout
        sceneLibrary.ensureScenes(for: layout)
        if let scene = sceneLibrary.selectedScene(layout: layout) {
            applySceneSnapshot(scene.snapshot)
        } else {
            settings.screenCrop = nil
            let layoutDefaults = RecordingSceneMutation.defaultsForLayout(
                layout,
                screenAspectRatio: screenAspectRatio(),
                cameraAspectRatio: cameraAspectRatio()
            )
            settings.selectedScenePreset = layoutDefaults.preset
            settings.sceneLayout = layoutDefaults.layout
        }
        restoreScreenSourceSelection(preservedScreenSource)
        recomputeSelectedPresetLayoutForCurrentSource()
        SceneLibraryStore.save(sceneLibrary, defaults: defaults)
        persist(saveSceneSnapshot: false)
        onScreenCaptureConfigurationChanged?()
        onCameraConfigurationChanged?()
        autoFitSelectedScreenWindow?()
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

    func setSource(_ source: CaptureSource, enabled: Bool) {
        guard state == .idle else {
            onMessage?("Capture source visibility is locked while recording.")
            return
        }
        applySourceVisibility(source, enabled: enabled)
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
        settings.outputDirectory = url
        settings.outputDirectoryBookmarkData = RecordingSettingsStore.bookmarkData(for: url)
        persist()
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

    func setSceneLayer(
        _ kind: SceneLayerKind,
        frame: CGRect,
        transition: RecordingSceneTransition = .cut
    ) {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        var screenCaptureConfigurationChanged = false
        switch kind {
        case .screen:
            let nextFrame = SceneLayerResizing.clamped(frame)
            if settings.sceneLayout.screenFrame != nextFrame, settings.screenCrop != nil {
                settings.screenCrop = nil
                screenCaptureConfigurationChanged = true
            }
            settings.sceneLayout.screenFrame = nextFrame
        case .camera:
            settings.sceneLayout.cameraFrame = SceneLayerResizing.clamped(frame)
        }
        persist()
        updateRecordingScene?(transition)
        if screenCaptureConfigurationChanged {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func setCameraCropAmount(_ amount: CGPoint) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraCropAmount = SourceCropGeometry.clampedAmount(amount)
        persist()
        updateRecordingScene?(.cut)
    }

    func setCameraCropPosition(_ position: CGPoint) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraCropPosition = SourceCropGeometry.clampedPosition(position)
        persist()
        updateRecordingScene?(.cut)
    }

    func setCanvasBackgroundStyle(_ style: CanvasBackgroundStyle) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasBackgroundStyle = style
        if !style.supportsBackgroundAnimation {
            settings.canvasBackgroundAnimated = false
        }
        persist()
        updateRecordingScene?(.cut)
    }

    func setCanvasBackgroundAnimated(_ animated: Bool) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasBackgroundAnimated = animated && settings.canvasBackgroundStyle.supportsBackgroundAnimation
        persist()
        updateRecordingScene?(.cut)
    }

    func setCanvasPadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.canvasPadding = CaptureValueClamps.canvasPadding(padding)
        persist()
        updateRecordingScene?(.cut)
        autoFitSelectedScreenWindow?()
    }

    func setCameraContentMode(_ mode: CameraContentMode) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraContentMode = mode
        persist()
        updateRecordingScene?(.cut)
    }

    func setScreenContentMode(_ mode: CameraContentMode) {
        guard sceneChangeIsAllowed() else { return }
        settings.screenContentMode = mode
        persist()
        updateRecordingScene?(.cut)
    }

    func setCameraFramePadding(_ padding: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraFramePadding = 0
        persist()
        updateRecordingScene?(.cut)
    }

    func setCameraShadowEnabled(_ enabled: Bool) {
        guard sceneChangeIsAllowed() else { return }
        settings.cameraShadowEnabled = enabled
        persist()
        updateRecordingScene?(.cut)
    }

    func setSceneLayout(_ sceneLayout: SceneLayout) {
        guard sceneChangeIsAllowed() else { return }
        let nextScreenFrame = SceneLayerResizing.clamped(sceneLayout.screenFrame)
        let nextCameraFrame = SceneLayerResizing.clamped(sceneLayout.cameraFrame)
        let screenCaptureConfigurationChanged = settings.sceneLayout.screenFrame != nextScreenFrame
            && settings.screenCrop != nil
        settings.selectedScenePreset = nil
        if screenCaptureConfigurationChanged {
            settings.screenCrop = nil
        }
        settings.sceneLayout.screenFrame = nextScreenFrame
        settings.sceneLayout.cameraFrame = nextCameraFrame
        settings.sceneLayout.layerOrder = sceneLayout.layerOrder
        persist()
        updateRecordingScene?(.cut)
        if screenCaptureConfigurationChanged {
            onScreenCaptureConfigurationChanged?()
        }
    }

    func previewSettings(for sceneLayout: SceneLayout) -> RecordingSettings {
        var previewSettings = settings
        previewSettings.selectedScenePreset = nil
        previewSettings.sceneLayout.screenFrame = SceneLayerResizing.clamped(sceneLayout.screenFrame)
        previewSettings.sceneLayout.cameraFrame = SceneLayerResizing.clamped(sceneLayout.cameraFrame)
        previewSettings.sceneLayout.layerOrder = sceneLayout.layerOrder
        return previewSettings
    }

    func resetSceneLayout() {
        guard sceneChangeIsAllowed() else { return }
        settings.selectedScenePreset = nil
        settings.sceneLayout = SceneLayout.defaultLayout(
            for: settings.layout,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        )
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        autoFitSelectedScreenWindow?()
    }

    func applyScenePreset(_ preset: ScenePreset) {
        guard sceneChangeIsAllowed() else { return }
        guard preset.supports(settings.layout) else { return }
        let cameraWasVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        settings = RecordingSceneMutation.applyingPreset(
            preset,
            to: settings,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        )
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        let cameraIsVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        if cameraWasVisible != cameraIsVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    func setScreenSplitHeight(_ height: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.layout == .vertical else { return }
        let cameraWasVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        settings = RecordingSceneMutation.applyingScreenSplit(
            height: height,
            to: settings,
            screenAspectRatio: screenAspectRatio()
        )
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        if !cameraWasVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    func setCameraInset(
        alignment: CameraInsetAlignment,
        shape: CameraInsetShape,
        size: CGFloat
    ) {
        guard sceneChangeIsAllowed() else { return }
        let screenWasVisible = settings.enabledSources.contains(.screen)
            && !settings.hiddenSources.contains(.screen)
        let cameraWasVisible = settings.enabledSources.contains(.camera)
            && !settings.hiddenSources.contains(.camera)
        let mutation = RecordingSceneMutation.applyingCameraInset(
            alignment: alignment,
            shape: shape,
            size: size,
            to: settings,
            screenAspectRatio: screenAspectRatio(),
            cameraAspectRatio: cameraAspectRatio()
        )
        settings = mutation.settings
        persist()
        updateRecordingScene?(.cut)
        if mutation.clearedScreenCrop || !screenWasVisible {
            onScreenCaptureConfigurationChanged?()
        }
        if !cameraWasVisible {
            onCameraConfigurationChanged?()
        }
        autoFitSelectedScreenWindow?()
    }

    @discardableResult
    func fitScreenToAvailableSlot() -> CGRect {
        guard sceneChangeIsAllowed() else { return settings.sceneLayout.screenFrame }
        let screenSlot = SceneSlotGeometry.screenSlot(
            in: settings.sceneLayout,
            enabledSources: settings.enabledSources
        )
        settings.selectedScenePreset = nil
        settings.sceneLayout.screenFrame = SceneLayerResizing.clamped(screenSlot)
        settings.screenCrop = nil
        persist()
        updateRecordingScene?(.sceneSwitch)
        onScreenCaptureConfigurationChanged?()
        return settings.sceneLayout.screenFrame
    }

    func fitScreenItemToFrontWindow(_ arrangement: ShortsWindowArrangement) {
        settings.screenCrop = CaptureValueClamps.normalizedRect(arrangement.screenCrop)
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
        onMessage?(arrangement.screenItemMessage)
    }

    func setSceneLayerOrder(_ order: [SceneLayerKind]) {
        guard sceneChangeIsAllowed() else { return }
        guard Set(order) == Set(SceneLayerKind.allCases),
              order.count == SceneLayerKind.allCases.count else {
            return
        }
        settings.selectedScenePreset = nil
        settings.sceneLayout.layerOrder = order
        persist()
        updateRecordingScene?(.sceneSwitch)
    }

    func fitSceneLayer(_ kind: SceneLayerKind, scale: CGFloat = 1) {
        let sourceAspectRatio: CGFloat
        switch kind {
        case .screen:
            sourceAspectRatio = screenAspectRatio()
        case .camera:
            sourceAspectRatio = cameraAspectRatio()
        }
        setSceneLayer(
            kind,
            frame: SceneLayerFit.frame(.init(
                kind: kind,
                layout: settings.sceneLayout,
                visibleSources: settings.visibleSources,
                removesCameraBackgroundAfterRecording: settings.removesCameraBackgroundAfterRecording,
                sourceAspectRatio: sourceAspectRatio,
                canvasAspectRatio: settings.layout.aspectRatio,
                scale: scale
            )),
            transition: .sceneSwitch
        )
    }

    func beginScreenCropEditing() {
        guard sceneChangeIsAllowed() else { return }
        if let next = RecordingSceneMutation.clearingIncompatibleScreenCrop(settings) {
            settings = next
            persist()
        }
        isEditingScreenCrop = true
        onScreenCaptureConfigurationChanged?()
    }

    func endScreenCropEditing() {
        guard isEditingScreenCrop else { return }
        isEditingScreenCrop = false
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenCrop(_ crop: CGRect?) {
        guard sceneChangeIsAllowed() else { return }
        if let crop {
            settings.screenCrop = CaptureValueClamps.persistedScreenCrop(crop)
        } else {
            settings.screenCrop = nil
        }
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
    }

    func setScreenWindowZoom(_ zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        let zoom = ScreenSourceZoomGeometry.clamped(zoom)
        guard abs(settings.screenWindowZoom - zoom) > 0.0001 else { return }
        settings.screenWindowZoom = zoom
        persist()
    }

    func applyPickedScreenCrop(_ crop: CGRect) {
        settings.screenCrop = CaptureValueClamps.persistedScreenCrop(crop)
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
    }

    func clearScreenCrop() {
        settings.screenCrop = nil
        persist()
        updateRecordingScene?(.cut)
        onScreenCaptureConfigurationChanged?()
    }

    func clearCustomScreenCrop() {
        guard settings.screenCrop != nil else { return }
        clearScreenCrop()
    }

    func screenSettingsWithoutCrop() -> RecordingSettings {
        var settings = settings
        settings.screenCrop = nil
        return settings
    }

    func noteScreenSourceAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0 else { return }
        currentPickedScreenSourceAspectRatio = aspectRatio
    }

    @discardableResult
    func refitCameraInsetFrame(sourceAspectRatio: CGFloat) -> Bool {
        let frame = settings.sceneLayout.cameraFrame
        guard SceneLayout.isCameraInsetFrame(frame) else { return false }
        let next = SceneLayout.cameraInsetFrame(
            for: settings.layout,
            alignment: SceneLayout.cameraInsetAlignment(for: frame),
            shape: SceneLayout.cameraInsetShape(for: frame, in: settings.layout),
            size: SceneLayout.cameraInsetSize(for: frame, in: settings.layout),
            sourceAspectRatio: sourceAspectRatio
        )
        let epsilon: CGFloat = 0.0005
        guard abs(next.minX - frame.minX) > epsilon
            || abs(next.minY - frame.minY) > epsilon
            || abs(next.width - frame.width) > epsilon
            || abs(next.height - frame.height) > epsilon else { return false }
        settings.sceneLayout.cameraFrame = next
        return true
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

    private func sceneChangeIsAllowed() -> Bool {
        guard allowsSceneChanges else {
            onMessage?("Scene layout is locked while saving.")
            return false
        }
        return true
    }
}
