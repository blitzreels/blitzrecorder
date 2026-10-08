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
            switchRecordingScreenSource(.init(binding: binding, autoFitWindowZoom: autoFitWindowZoom))
            return
        }
        cancelPendingScreenWindowFits()
        studio.applyIdleScreenSource(binding)
        screenSourcePickerRecents.record(binding)
        if let autoFitWindowZoom, binding.kind != .display {
            autoFitScreenSourceWindow(binding, zoom: autoFitWindowZoom)
        }
    }

    struct RecordingScreenSourceRequest {
        let binding: ScreenSourceBinding
        let autoFitWindowZoom: CGFloat?
    }

    func switchRecordingScreenSource(_ request: RecordingScreenSourceRequest) {
        let binding = request.binding
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
                let captureSettings = currentLocalCaptureSettings()
                let filter = try await resolvedScreenFilter(for: captureSettings)
                try await takeRecording.updateScreenCapture(settings: captureSettings, pickedScreenFilter: filter)
                committedRecordingSettings = settings
                screenSourcePickerRecents.record(binding)
                persistSettings()
                updateRecordingSceneTimeline(transition: .cut)
                onScreenCaptureConfigurationChanged?()
                onMessage?(RecordingStopCopy.screenSwitched(binding.displayName))
                if let zoom = request.autoFitWindowZoom, binding.kind != .display {
                    autoFitScreenSourceWindow(binding, zoom: zoom)
                }
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
        return ScreenSourceCatalog.options(.init(
            content: content,
            recentBundleIdentifiers: screenSourcePickerRecents.bundleIdentifiers(),
            frontToBackWindowIDs: ScreenSourceCatalog.frontToBackWindowIDs(),
            includesRecorderUI: settings.includesRecorderUI
        ))
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
            selectionPolicy: request.selectionPolicy,
            includesRecorderUI: settings.includesRecorderUI
        ))
        let persistentBinding = await ScreenCaptureGeometry.persistentBinding(forPickedContent: pickedFilter)
        screenSourcePickerRecents.record(persistentBinding)
        guard state.allowsScreenContentPickerPresentation else {
            throw RecorderError.screenSelectionCancelled
        }
        guard request.selectionPolicy.accepts(persistentBinding?.kind) else {
            throw RecorderError.screenWindowRequired
        }
        let filter = await ScreenCaptureGeometry.applyingRecorderVisibility(.init(
            filter: ScreenCaptureGeometry.normalizedPickedFilter(pickedFilter),
            includesRecorderUI: settings.includesRecorderUI
        ))
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
                let localSettings = currentLocalCaptureSettings()
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

    func pickedScreenFilter(for settings: RecordingSettings) -> SCContentFilter? {
        screenSourceSelection.activeFilter(for: settings)
    }

    func resolvedScreenFilter(for settings: RecordingSettings) async throws -> SCContentFilter? {
        guard settings.enabledSources.contains(.screen)
                || settings.enabledSources.contains(.systemAudio) else {
            return nil
        }
        if let pickedFilter = pickedScreenFilter(for: settings) {
            return await ScreenCaptureGeometry.applyingRecorderVisibility(.init(
                filter: pickedFilter, includesRecorderUI: settings.includesRecorderUI))
        }
        guard permissionGate.hasScreenCaptureAccess,
              settings.screenSourceBinding?.isConcreteSelection == true else {
            return nil
        }
        let source = try await ScreenSourceLookup.resolve {
            let content = try await SCShareableContent.current
            return try ScreenCaptureGeometry.screenSource(for: settings, content: content)
        }
        return source.filter
    }
}
