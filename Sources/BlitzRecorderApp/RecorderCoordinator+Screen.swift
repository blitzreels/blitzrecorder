import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
    var hasActivePickedScreenContent: Bool {
        screenSourceSelection.hasActivePickedContent
    }

    var activePickedScreenContentKind: ScreenSourceBinding.Kind? {
        screenSourceSelection.activePickedContentKind(for: settings)
    }

    var hasActiveScreenSourceSelection: Bool {
        ScreenPreviewLifecycle.sourceIsAvailable(.init(
            settings: settings,
            hasPersistentScreenCaptureAccess: permissionGate.hasScreenCaptureAccess,
            hasActivePickedContent: screenSourceSelection.hasActivePickedContent
        ))
    }

    func setScreenSource(_ binding: ScreenSourceBinding, autoFitWindowZoom: CGFloat? = nil) {
        guard state.allowsScreenContentPickerPresentation else { return }
        if state == .recording || state == .paused {
            switchRecordingScreenSource(binding)
            return
        }
        cancelPendingScreenWindowFits()
        studio.applyIdleScreenSource(binding)
        screenSourcePickerRecents.record(binding)
        if let autoFitWindowZoom, binding.kind != .display {
            autoFitScreenSourceWindow(binding, zoom: autoFitWindowZoom)
        }
    }

    func switchRecordingScreenSource(_ binding: ScreenSourceBinding) {
        let previousTransaction = screenReconfiguration.pickerTransactionTask
        let previousConfiguration = screenReconfiguration.configurationTask
        let transactionID = UUID()
        screenReconfiguration.pickerTransactionID = transactionID
        screenReconfiguration.pickerTransactionTask = Task { @MainActor [weak self] in
            await previousTransaction?.value
            await previousConfiguration?.value
            guard let self else { return }
            defer {
                if screenReconfiguration.pickerTransactionID == transactionID {
                    screenReconfiguration.pickerTransactionID = nil
                    screenReconfiguration.pickerTransactionTask = nil
                }
            }
            guard state == .recording || state == .paused else { return }
            let previousSettings = settings
            let previousSelection = screenSourceSelection.runtimeState()
            let previousAspectRatio = currentPickedScreenSourceAspectRatio
            cancelPendingScreenWindowFits()
            settings = screenSourceSelection.selectBinding(.init(binding: binding, settings: settings))
            settings.enabledSources.insert(.screen)
            settings.hiddenSources.remove(.screen)
            currentPickedScreenSourceAspectRatio = nil
            do {
                let captureSettings = localCaptureSettings(
                    usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
                )
                let filter = try await resolvedScreenFilter(for: captureSettings)
                try await takeRecording.updateScreenCapture(settings: captureSettings, pickedScreenFilter: filter)
                committedRecordingSettings = settings
                screenSourcePickerRecents.record(binding)
                persistSettings()
                updateRecordingSceneTimeline(transition: .cut)
                onScreenCaptureConfigurationChanged?()
                onMessage?(RecordingStopCopy.screenSwitched(binding.displayName))
            } catch {
                settings = previousSettings
                screenSourceSelection.restoreRuntimeState(previousSelection)
                currentPickedScreenSourceAspectRatio = previousAspectRatio
                onScreenCaptureConfigurationChanged?()
                if CaptureSourceRetargetFailure.shouldStopTake(for: error) {
                    stop()
                    onMessage?(RecordingStopCopy.sourceSwitchStoppedTake)
                } else {
                    onMessage?(RecordingStopCopy.screenSwitchFailed(error))
                }
            }
        }
    }

    func targetWindowInfo() throws -> TargetWindowInfo {
        try ShortsWindowArranger.frontWindowInfo(displayID: settings.selectedDisplayID)
    }

    func fitFrontWindowForShorts() {
        fitFrontWindowForShorts(zoom: 1)
    }

    func fitScreenItemToFrontWindow() {
        guard sceneChangeIsAllowed() else { return }
        guard ensureAccessibilityForWindowControls() else { return }

        do {
            let arrangement = try ShortsWindowArranger.screenItemForFrontWindow(
                displayID: settings.selectedDisplayID
            )
            settings.screenCrop = CaptureValueClamps.normalizedRect(arrangement.screenCrop)
            persistSettings()
            updateRecordingSceneIfNeeded()
            onScreenCaptureConfigurationChanged?()
            onMessage?(arrangement.screenItemMessage)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    func fitFrontWindowForShorts(zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        let revision = beginScreenWindowFit()
        guard ensureAccessibilityForWindowControls() else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let arrangement = try await ShortsWindowArranger.fitFrontWindow(
                    displayID: settings.selectedDisplayID,
                    captureLayout: settings.layout,
                    sceneLayout: settings.sceneLayout,
                    enabledSources: settings.visibleSources,
                    canvasPadding: settings.canvasPadding,
                    zoom: zoom
                )
                guard self.screenWindowFitRevision == revision else { return }
                settings.screenCrop = CaptureValueClamps.normalizedRect(arrangement.screenCrop)
                persistSettings()
                updateRecordingSceneIfNeeded()
                onScreenCaptureConfigurationChanged?()
                onMessage?(arrangement.message)
            } catch {
                guard self.screenWindowFitRevision == revision else { return }
                onMessage?(error.localizedDescription)
            }
        }
    }

    func fitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard ensureAccessibilityForWindowControls() else { return }
        let revision = beginScreenWindowFit()

        Task { [weak self, binding] in
            guard let self else { return }
            do {
                guard let arrangement = try await self.screenSourceWindowArrangement(
                    for: binding,
                    zoom: zoom,
                    revision: revision
                ) else { return }
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: true)
                self.onMessage?(arrangement.resizedMessage)
            } catch {
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.onScreenCaptureConfigurationChanged?()
                self.onMessage?(error.localizedDescription)
            }
        }
    }

    func fitPickedScreenWindowToSlot(zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.usesPickedScreenContent,
              let pickedScreenFilter = screenSourceSelection.pickedContentFilter else {
            onMessage?("Pick a screen source before resizing its window.")
            return
        }
        guard settings.screenSourceBinding?.kind != .display else {
            onMessage?("A display has no source window to resize. Use Screen framing instead.")
            return
        }
        guard ensureAccessibilityForWindowControls() else { return }
        let revision = beginScreenWindowFit()

        Task { [weak self, pickedScreenFilter] in
            guard let self else { return }
            _ = await self.fitPickedScreenWindow(
                pickedScreenFilter,
                zoom: zoom,
                shouldUpdateCapture: true,
                revision: revision
            )
        }
    }

    func zoomScreenSourceContent(_ direction: AppContentZoomDirection) {
        guard ensureAccessibilityForWindowControls() else { return }
        let context = screenSourceActionContext()

        Task { [weak self] in
            guard let self else { return }
            guard let processID = await self.targetProcessIDForScreenContentZoom() else {
                self.onMessage?("Select an app or window before changing app content size.")
                return
            }
            guard self.screenSourceActionContext() == context else { return }

            guard AppContentZoomer.apply(AppContentZoomer.Request(
                direction: direction,
                processID: processID
            )) else {
                self.onMessage?("Could not map the app content shortcut for this keyboard.")
                return
            }
            self.onMessage?("\(direction.messageVerb) selected app content.")
        }
    }

    func autoFitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        guard permissionGate.hasAccessibilityAccess else { return }
        let revision = beginScreenWindowFit()
        Task { [weak self, binding] in
            guard let self else { return }
            do {
                guard let arrangement = try await ScreenWindowFitRetry.run({
                    try await self.screenSourceWindowArrangement(
                        for: binding,
                        zoom: zoom,
                        revision: revision
                    )
                }) else { return }
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: true)
                self.onMessage?(arrangement.resizedMessage)
            } catch {
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.onMessage?(error.localizedDescription)
            }
        }
    }

    func autoFitSelectedScreenWindowToSceneSlot() {
        switch ScreenWindowFit.RecordingStartPlan.make(
            visibleScreen: settings.visibleSources.contains(.screen),
            hasAccessibility: permissionGate.hasAccessibilityAccess,
            usesPickedScreenContent: settings.usesPickedScreenContent,
            pickedKind: activePickedScreenContentKind,
            binding: settings.screenSourceBinding
        ) {
        case .picked:
            guard let filter = screenSourceSelection.pickedContentFilter else { return }
            Task { [weak self, filter] in
                await self?.autoFitPickedScreenWindow(filter)
            }
        case .binding(let binding):
            autoFitScreenSourceWindow(binding, zoom: settings.screenWindowZoom)
        case .skip:
            return
        }
    }

    func screenSourceWindowArrangement(
        for binding: ScreenSourceBinding,
        zoom: CGFloat,
        revision: Int
    ) async throws -> ShortsWindowArrangement? {
        try await ScreenWindowFit.arrangement(
            .init(
                binding: binding,
                zoom: zoom,
                fallbackDisplayID: targetDisplayID(for: binding),
                captureLayout: settings.layout,
                sceneLayout: settings.sceneLayout,
                enabledSources: settings.visibleSources,
                canvasPadding: settings.canvasPadding
            ),
            isCurrent: { isCurrentScreenSourceWindowFit(revision, binding: binding) }
        )
    }

    func beginScreenWindowFit() -> Int {
        ShortsWindowArranger.cancelPendingFits()
        screenWindowFitRevision += 1
        return screenWindowFitRevision
    }

    func cancelPendingScreenWindowFits() {
        ShortsWindowArranger.cancelPendingFits()
        screenWindowFitRevision += 1
    }

    func isCurrentScreenSourceWindowFit(
        _ revision: Int,
        binding: ScreenSourceBinding
    ) -> Bool {
        revision == screenWindowFitRevision
            && settings.screenSourceBinding == binding
            && !settings.usesPickedScreenContent
    }

    func isCurrentPickedScreenWindowFit(_ revision: Int) -> Bool {
        revision == screenWindowFitRevision && settings.usesPickedScreenContent
    }

    func screenSourceActionContext() -> ScreenSourceActionContext {
        ScreenSourceActionContext(
            screenWindowFitRevision: screenWindowFitRevision,
            screenContentSelectionRevision: screenContentSelectionRevision,
            screenSourceBinding: settings.screenSourceBinding,
            usesPickedScreenContent: settings.usesPickedScreenContent
        )
    }

    func targetProcessIDForScreenContentZoom() async -> pid_t? {
        await AppContentZoomTargetResolver.processID(
            settings: settings,
            pickedWindowProcessID: { [weak self] in
                guard let filter = self?.screenSourceSelection.pickedContentFilter else { return nil }
                return await ScreenCaptureGeometry.pickedWindowTarget(for: filter)?.pid
            },
            applicationProcessID: { binding in
                ScreenWindowFit.processID(forApplicationBinding: binding)
            },
            windowProcessID: { binding in
                await ScreenCaptureGeometry.windowTarget(for: binding)?.pid
            },
            frontWindowProcessID: { [weak self] displayID in
                self?.frontWindowProcessIDForScreenContentZoom(displayID: displayID)
            }
        )
    }

    func frontWindowProcessIDForScreenContentZoom(displayID: String?) -> pid_t? {
        try? ShortsWindowArranger.frontWindowInfo(displayID: displayID).processID
    }

    func targetDisplayID(for binding: ScreenSourceBinding) -> String? {
        binding.displayID ?? settings.selectedDisplayID
    }

    func resizeTargetWindow(widthDelta: CGFloat, heightDelta: CGFloat) {
        guard ensureAccessibilityForWindowControls() else { return }

        clearCustomScreenCrop()
        do {
            let arrangement = try ShortsWindowArranger.resizeFrontWindow(
                displayID: settings.selectedDisplayID,
                widthDelta: widthDelta,
                heightDelta: heightDelta
            )
            onMessage?(arrangement.resizedMessage)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    func setTargetWindowSize(width: CGFloat, height: CGFloat) {
        guard ensureAccessibilityForWindowControls() else { return }

        clearCustomScreenCrop()
        do {
            let arrangement = try ShortsWindowArranger.setFrontWindowSize(
                displayID: settings.selectedDisplayID,
                width: width,
                height: height
            )
            onMessage?(arrangement.resizedMessage)
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    func ensureAccessibilityForWindowControls() -> Bool {
        if permissionGate.hasAccessibilityAccess {
            return true
        }

        Task { _ = await permissionGate.requestAccessibilityAccessForWindowControls() }
        if permissionGate.hasAccessibilityAccess {
            return true
        }

        permissionGate.openAccessibilitySettings()
        onMessage?("Enable Accessibility for BlitzRecorder to resize target windows.")
        return false
    }

    func currentScreenSourceAspectRatio() -> CGFloat {
        ScreenCaptureGeometry.resolvedSourceAspectRatio(.init(
            isEditingScreenCrop: isEditingScreenCrop,
            bindingKind: settings.screenSourceBinding?.kind,
            pickedAspectRatio: currentPickedScreenSourceAspectRatio,
            usesPickedScreenContent: settings.usesPickedScreenContent,
            pickedFilterAspectRatio: screenSourceSelection.pickedContentFilter.map(
                ScreenCaptureGeometry.pickedContentAspectRatio(for:)
            ),
            selectedDisplayID: settings.selectedDisplayID,
            settings: isEditingScreenCrop ? screenSettingsWithoutCrop() : settings
        ))
    }

    func currentCameraSourceAspectRatio() -> CGFloat {
        knownCameraSourceAspectRatio() ?? SceneLayout.cameraAspectRatio
    }

    func knownCameraSourceAspectRatio() -> CGFloat? {
        if RemoteCameraProviderID.serviceID(from: settings.selectedCameraID) != nil {
            let unknown: CGFloat = -1
            let aspectRatio = remoteCamera.currentCameraSourceAspectRatio(fallback: unknown)
            return aspectRatio > 0 ? aspectRatio : nil
        }
        if let device = LocalCameraSessionConfiguration.selectedCamera(settings: settings, fallbackToDefault: true) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            if dimensions.width > 0, dimensions.height > 0 {
                return CGFloat(dimensions.width) / CGFloat(dimensions.height)
            }
        }
        return nil
    }

    func refitCameraInsetToCurrentCamera() {
        guard state == .idle, studio.allowsSceneChanges else { return }
        guard refitCameraInsetFrameForCurrentSource() else { return }
        persistSettings()
        updateRecordingSceneIfNeeded()
    }

    func selectScreenCrop() async throws {
        let crop = try await screenCropPicker.pick(
            displayID: settings.selectedDisplayID,
            initialCrop: settings.screenCrop
        )
        guard !crop.isNull, crop.width > 0, crop.height > 0 else {
            throw ScreenCropPickerError.selectionTooSmall
        }

        settings.screenCrop = CaptureValueClamps.persistedScreenCrop(crop)
        persistSettings()
        updateRecordingSceneIfNeeded()
        onScreenCaptureConfigurationChanged?()
    }

    func availableDisplays() async -> [SourceOption] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        return displays.map { displayID in
            let width = CGDisplayPixelsWide(displayID)
            let height = CGDisplayPixelsHigh(displayID)
            return SourceOption(id: "\(displayID)", name: "Display \(displayID) (\(width)x\(height))")
        }
    }

    func availableScreenSources() async -> [ScreenSourceOption] {
        guard permissionGate.hasScreenCaptureAccess,
              let content = try? await SCShareableContent.current else {
            return []
        }
        screenThumbnailProvider.updateContent(content)
        return ScreenSourceCatalog.options(
            content: content,
            recentBundleIdentifiers: screenSourcePickerRecents.bundleIdentifiers()
        )
    }

    func screenSourceThumbnail(_ binding: ScreenSourceBinding) async -> NSImage? {
        guard state.allowsScreenContentPickerPresentation, permissionGate.hasScreenCaptureAccess else { return nil }
        return await screenThumbnailProvider.image(.init(binding: binding, settings: settings))
    }

    func pickScreenContent() async throws {
        try await pickScreenContent(.init(
            activatesScreenSource: false,
            selectionPolicy: .anyScreenContent
        ))
    }

    func pickScreenSource() async throws {
        try await pickScreenContent(.init(
            activatesScreenSource: true,
            selectionPolicy: .appWindow
        ))
    }

    func pickFullScreenSource() async throws {
        try await pickScreenContent(.init(
            activatesScreenSource: true,
            selectionPolicy: .fullScreen
        ))
    }

    func pickScreenContent(_ request: PickScreenContentRequest) async throws {
        let previousPickerTransactionTask = screenReconfiguration.pickerTransactionTask
        let pendingConfigurationTask: Task<Void, Never>?
        if state == .recording || state == .paused {
            pendingConfigurationTask = screenReconfiguration.configurationTask
        } else {
            pendingConfigurationTask = nil
        }

        let transactionID = UUID()
        let transactionTask = Task { @MainActor [weak self] in
            await previousPickerTransactionTask?.value
            await pendingConfigurationTask?.value
            guard let self,
                  self.state.allowsScreenContentPickerPresentation else {
                throw RecorderError.screenSelectionCancelled
            }
            try await self.performScreenContentPick(request)
        }
        let barrierTask = Task { @MainActor in
            _ = try? await transactionTask.value
        }
        screenReconfiguration.pickerTransactionID = transactionID
        screenReconfiguration.pickerTransactionTask = barrierTask
        defer {
            if screenReconfiguration.pickerTransactionID == transactionID {
                screenReconfiguration.pickerTransactionID = nil
                screenReconfiguration.pickerTransactionTask = nil
            }
        }
        try await transactionTask.value
    }

    func performScreenContentPick(_ request: PickScreenContentRequest) async throws {
        let pickedFilter = try await screenContentPicker.pick(.init(
            activeStream: takeRecording.activeScreenCaptureStream,
            selectionPolicy: request.selectionPolicy
        ))
        let persistentBinding = await ScreenCaptureGeometry.persistentBinding(forPickedContent: pickedFilter)
        screenSourcePickerRecents.record(persistentBinding)
        guard state.allowsScreenContentPickerPresentation else {
            throw RecorderError.screenSelectionCancelled
        }
        guard request.selectionPolicy.accepts(persistentBinding?.kind) else {
            throw RecorderError.screenWindowRequired
        }
        let filter = ScreenCaptureGeometry.normalizedPickedFilter(pickedFilter)
        let pickedAspectRatio = ScreenCaptureGeometry.pickedContentAspectRatio(for: filter)
        let previousSettings = settings
        let previousSelectionState = screenSourceSelection.runtimeState()
        let previousPickedScreenSourceAspectRatio = currentPickedScreenSourceAspectRatio
        cancelPendingScreenWindowFits()
        screenContentSelectionRevision += 1
        settings = PickScreenContentRequest.applied(
            to: previousSettings,
            activatesScreenSource: request.activatesScreenSource,
            pickedAspectRatio: pickedAspectRatio,
            isIdle: state == .idle
        ) { settings in
            screenSourceSelection.selectPickedContent(
                ScreenSourceSelection.PickedContentRequest(
                    filter: filter,
                    persistentBinding: persistentBinding,
                    fallbackSourceKind: request.selectionPolicy.fallbackSourceKind,
                    settings: settings
                )
            )
        }
        currentPickedScreenSourceAspectRatio = pickedAspectRatio

        let updatesActiveRecording = PickScreenContentRequest.updatesActiveCapture(state)
        if updatesActiveRecording {
            do {
                let localSettings = localCaptureSettings(
                    usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
                )
                try await takeRecording.updateScreenCapture(
                    settings: localSettings,
                    pickedScreenFilter: filter
                )
                committedRecordingSettings = settings
            } catch {
                settings = previousSettings
                screenSourceSelection.restoreRuntimeState(previousSelectionState)
                currentPickedScreenSourceAspectRatio = previousPickedScreenSourceAspectRatio
                if CaptureSourceRetargetFailure.shouldStopTake(for: error) {
                    stop()
                    onRequestForeground?()
                    onMessage?(RecordingStopCopy.sourceSwitchStoppedTake)
                }
                throw error
            }
        }

        persistSettings()
        switch PickScreenContentRequest.persistAction(updatesActiveRecording: updatesActiveRecording) {
        case .cutTimeline:
            updateRecordingSceneTimeline(transition: .cut)
        case .updateIfNeeded:
            updateRecordingSceneIfNeeded()
        }
        onScreenCaptureConfigurationChanged?()
        onRequestForeground?()
        if request.selectionPolicy.shouldAutoFitPickedWindow {
            await autoFitPickedScreenWindow(filter)
        }
    }

    func autoFitPickedScreenWindow(_ filter: SCContentFilter) async {
        guard state.allowsScreenContentPickerPresentation,
              permissionGate.hasAccessibilityAccess else {
            return
        }
        let revision = beginScreenWindowFit()
        _ = await fitPickedScreenWindow(
            filter,
            zoom: settings.screenWindowZoom,
            shouldUpdateCapture: true,
            revision: revision
        )
    }

    func fitPickedScreenWindow(
        _ filter: SCContentFilter,
        zoom: CGFloat,
        shouldUpdateCapture: Bool,
        revision: Int
    ) async -> Bool {
        guard isCurrentPickedScreenWindowFit(revision) else {
            return false
        }

        do {
            let arrangement = try await ScreenWindowFitRetry.run {
                try await ScreenWindowFit.pickedArrangement(
                    .init(
                        filter: filter,
                        binding: self.settings.screenSourceBinding,
                        zoom: zoom,
                        fallbackDisplayID: self.settings.selectedDisplayID,
                        captureLayout: self.settings.layout,
                        sceneLayout: self.settings.sceneLayout,
                        enabledSources: self.settings.visibleSources,
                        canvasPadding: self.settings.canvasPadding
                    ),
                    isCurrent: { self.isCurrentPickedScreenWindowFit(revision) }
                )
            }
            guard isCurrentPickedScreenWindowFit(revision) else {
                return false
            }
            applyFittedScreenWindowArrangement(arrangement, shouldUpdateCapture: false)
            if shouldUpdateCapture {
                onScreenCaptureConfigurationChanged?()
                onMessage?(arrangement.resizedMessage)
            }
            return true
        } catch {
            guard isCurrentPickedScreenWindowFit(revision) else {
                return false
            }
            if shouldUpdateCapture {
                onMessage?(error.localizedDescription)
            }
            return false
        }
    }

    func updateRecordingSceneIfNeeded(transition: RecordingSceneTransition = .cut) {
        let screenFilter = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentFilter
            : nil
        let scene = RecordingScene.live(settings: settings, pickedFilter: screenFilter)
        takeRecording.updateScene(scene, transition: transition)
        if (state == .recording || state == .paused),
           settings.enabledSources.contains(.screen) {
            let pendingEvent = takeRecording.pendingSceneEvent(
                scene: scene,
                transition: transition
            )
            updateActiveScreenCaptureConfigurationIfNeeded(pendingEvent: pendingEvent)
        } else {
            takeRecording.appendSceneEventIfNeeded(scene, state: state, transition: transition)
            if state == .recording || state == .paused {
                committedRecordingSettings = settings
            }
        }
        synchronizeActiveCaptureSourcesIfNeeded()
    }

    func updateRecordingSceneTimeline(transition: RecordingSceneTransition) -> RecordingScene {
        let screenFilter = settings.usesPickedScreenContent
            ? screenSourceSelection.pickedContentFilter
            : nil
        let scene = RecordingScene.live(
            settings: settings,
            pickedFilter: screenFilter
        )
        takeRecording.updateScene(scene, transition: transition)
        takeRecording.appendSceneEventIfNeeded(scene, state: state, transition: transition)
        return scene
    }

    func updateActiveScreenCaptureConfigurationIfNeeded(
        pendingEvent: PendingRecordingSceneEvent
    ) {
        guard state == .recording || state == .paused,
              settings.enabledSources.contains(.screen) else {
            return
        }

        let requestedSettings = settings
        screenReconfiguration.configurationRevision += 1
        let generation = screenReconfiguration.configurationRevision
        let previousTask = screenReconfiguration.configurationTask
        let pickerTransactionTask = screenReconfiguration.pickerTransactionTask
        let pickerQueuedRevision: Int?
        if pickerTransactionTask == nil {
            pickerQueuedRevision = nil
        } else {
            screenReconfiguration.pickerQueuedRevision += 1
            pickerQueuedRevision = screenReconfiguration.pickerQueuedRevision
        }
        let task = Task {
            [
                weak self,
                previousTask,
                pickerTransactionTask,
                generation,
                pendingEvent,
                pickerQueuedRevision,
                requestedSettings
            ] in
            await pickerTransactionTask?.value
            await previousTask?.value
            guard let self,
                  self.shouldApplyActiveScreenCaptureConfiguration(generation: generation),
                  !ScreenCaptureGeometry.isStalePickerQueuedRevision(
                    pickerQueuedRevision,
                    current: self.screenReconfiguration.pickerQueuedRevision
                  ) else {
                return
            }
            let effectiveSettings = pickerTransactionTask == nil
                ? requestedSettings
                : self.settings
            let effectiveEvent: PendingRecordingSceneEvent
            if pickerTransactionTask == nil {
                effectiveEvent = pendingEvent
            } else {
                let currentFilter = effectiveSettings.usesPickedScreenContent
                    ? self.screenSourceSelection.pickedContentFilter
                    : nil
                let currentScene = RecordingScene.live(
                    settings: effectiveSettings,
                    pickedFilter: currentFilter
                )
                effectiveEvent = pendingEvent.resolving(scene: currentScene)
            }
            let captureSettings = self.localCaptureSettings(
                usesRemoteCamera: effectiveSettings.enabledSources.contains(.camera)
                    && self.isRemoteCameraSelected
            )
            do {
                let pickedScreenFilter = try await self.resolvedScreenFilter(for: captureSettings)
                try await self.takeRecording.updateScreenCapture(
                    settings: captureSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
                let resolvedScene = RecordingScene.live(
                    settings: effectiveSettings,
                    pickedFilter: pickedScreenFilter
                )
                self.takeRecording.appendPendingSceneEvent(
                    effectiveEvent.resolving(scene: resolvedScene),
                    state: self.state
                )
                self.committedRecordingSettings = effectiveSettings
            } catch {
                self.reportActiveScreenCaptureConfigurationFailure(error, generation: generation)
            }
        }
        screenReconfiguration.configurationTask = task
    }

    func cancelPendingActiveScreenCaptureConfigurationUpdate() {
        screenReconfiguration.configurationRevision += 1
        screenReconfiguration.configurationTask?.cancel()
        screenReconfiguration.configurationTask = nil
    }

    func shouldApplyActiveScreenCaptureConfiguration(generation: Int) -> Bool {
        !Task.isCancelled
            && screenReconfiguration.configurationRevision == generation
            && (state == .recording || state == .paused || state == .finishing)
    }

    func reportActiveScreenCaptureConfigurationFailure(_ error: Error, generation: Int) {
        if CaptureSourceRetargetFailure.shouldStopTake(for: error) {
            cancelPendingActiveScreenCaptureConfigurationUpdate()
            stop()
            onRequestForeground?()
            onMessage?(RecordingStopCopy.screenCaptureUpdateStoppedTake)
            return
        }
        guard screenReconfiguration.configurationRevision == generation else { return }
        cancelPendingActiveScreenCaptureConfigurationUpdate()
        if let committedRecordingSettings {
            settings = committedRecordingSettings
            persistSettings()
            if let committedScene = takeRecording.sceneEvents.last?.scene {
                takeRecording.updateScene(committedScene, transition: .cut)
            }
            onScreenCaptureConfigurationChanged?()
        }
        onMessage?("Screen capture update failed: \(error.recorderFailureDescription)")
    }

    func synchronizeActiveCaptureSourcesIfNeeded() {
        guard !takeRecording.isUsingLiveCompositor,
              state == .recording || state == .paused else {
            return
        }
        if settings.enabledSources.contains(.screen),
           !settings.usesPickedScreenContent,
           !hasScreenCaptureAccess() {
            onMessage?("Pick a screen or enable Screen Recording before adding screen capture to this recording.")
            return
        }
        let localSettings = localCaptureSettings(
            usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
        )
        Task { [weak self, localSettings] in
            do {
                let pickedScreenFilter = try await self?.resolvedScreenFilter(for: localSettings)
                try await self?.takeRecording.startEnabledSources(
                    settings: localSettings,
                    pickedScreenFilter: pickedScreenFilter
                )
            } catch {
                self?.onMessage?("Source could not be added to recording: \(error.localizedDescription)")
            }
        }
    }

    func pickedScreenFilter(for settings: RecordingSettings) -> SCContentFilter? {
        screenSourceSelection.activeFilter(for: settings)
    }

    func resolvedScreenFilter(for settings: RecordingSettings) async throws -> SCContentFilter? {
        guard settings.enabledSources.contains(.screen)
                || settings.enabledSources.contains(.systemAudio) else {
            return nil
        }
        if let pickedFilter = pickedScreenFilter(for: settings) {
            return pickedFilter
        }
        guard permissionGate.hasScreenCaptureAccess,
              settings.screenSourceBinding?.isConcreteSelection == true else {
            return nil
        }
        let content = try await SCShareableContent.current
        return try ScreenCaptureGeometry.screenSource(for: settings, content: content).filter
    }

}
