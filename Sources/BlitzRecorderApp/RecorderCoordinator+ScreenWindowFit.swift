import AppKit
import AVFoundation
import BlitzRecorderCore
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
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
            publishWindowFitMessage(arrangement.screenItemMessage)
        } catch {
            publishWindowFitMessage(error.localizedDescription)
        }
    }

    func admitWindowFit(_ request: WindowFitAdmission) -> Bool {
        let decision = windowFitLoopGuard.admit(.init(key: request.key, now: Date(), origin: request.origin))
        layoutLog.notice("window fit \(request.reason, privacy: .public) key=\(request.key, privacy: .public) decision=\(String(describing: decision), privacy: .public) state=\(String(describing: self.state), privacy: .public)")
        switch decision {
        case .allow:
            publishWindowFitMessage("Resizing source window…")
            return true
        case .pauseNow:
            publishWindowFitMessage("This window keeps going back to its own size, so automatic fitting is paused for this take. Use Fit window to try again.")
            return false
        case .paused:
            return false
        }
    }

    func publishWindowFitMessage(_ message: String) {
        onScreenWindowFitMessage?(message)
        onMessage?(message)
    }

    func resetWindowFitLoopGuard() {
        windowFitLoopGuard.reset()
    }

    func fitFrontWindowForShorts(zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard admitWindowFit(.init(key: "front", reason: "front window", origin: .userInitiated)) else { return }
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
                publishWindowFitMessage(arrangement.message)
            } catch {
                guard self.screenWindowFitRevision == revision else { return }
                publishWindowFitMessage(error.localizedDescription)
            }
        }
    }

    func fitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard admitWindowFit(.init(key: binding.id, reason: "source window", origin: .userInitiated)) else { return }
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
                self.publishWindowFitMessage(arrangement.resizedMessage)
            } catch {
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.onScreenCaptureConfigurationChanged?()
                self.publishWindowFitMessage(error.localizedDescription)
            }
        }
    }

    func fitPickedScreenWindowToSlot(zoom: CGFloat) {
        guard sceneChangeIsAllowed() else { return }
        guard settings.usesPickedScreenContent,
              let pickedScreenFilter = screenSourceSelection.pickedContentFilter else {
            publishWindowFitMessage("Pick a screen source before resizing its window.")
            return
        }
        guard settings.screenSourceBinding?.kind != .display else {
            publishWindowFitMessage("A display has no source window to resize. Use Screen framing instead.")
            return
        }
        guard ensureAccessibilityForWindowControls() else { return }
        guard admitWindowFit(.init(key: "picked", reason: "picked window", origin: .userInitiated)) else { return }
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
                self.publishWindowFitMessage("Select an app or window before changing app content size.")
                return
            }
            guard self.screenSourceActionContext() == context else { return }

            guard AppContentZoomer.apply(AppContentZoomer.Request(
                direction: direction,
                processID: processID
            )) else {
                self.publishWindowFitMessage("Could not map the app content shortcut for this keyboard.")
                return
            }
            self.publishWindowFitMessage("\(direction.messageVerb) selected app content.")
        }
    }

    func autoFitScreenSourceWindow(_ binding: ScreenSourceBinding, zoom: CGFloat) {
        guard permissionGate.hasAccessibilityAccess else { return }
        guard admitWindowFit(.init(key: binding.id, reason: "auto source window", origin: .automatic)) else { return }
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
                self.publishWindowFitMessage(arrangement.resizedMessage)
            } catch {
                guard self.isCurrentScreenSourceWindowFit(revision, binding: binding) else { return }
                self.publishWindowFitMessage(error.localizedDescription)
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
        _ = beginScreenWindowFit()
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
            publishWindowFitMessage(arrangement.resizedMessage)
        } catch {
            publishWindowFitMessage(error.localizedDescription)
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
            publishWindowFitMessage(arrangement.resizedMessage)
        } catch {
            publishWindowFitMessage(error.localizedDescription)
        }
    }

    func ensureAccessibilityForWindowControls() -> Bool {
        if permissionGate.hasAccessibilityAccess {
            return true
        }

        Task { [weak self] in
            guard let self else { return }
            let result = await permissionGate.requestAccessibilityAccessForWindowControls()
            if result.status == .needsSettings {
                publishWindowFitMessage(result.message)
            }
        }

        return false
    }

    func autoFitPickedScreenWindow(_ filter: SCContentFilter) async {
        guard state.allowsScreenContentPickerPresentation,
              permissionGate.hasAccessibilityAccess else {
            return
        }
        guard admitWindowFit(.init(key: "picked", reason: "auto picked window", origin: .automatic)) else { return }
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
                publishWindowFitMessage(arrangement.resizedMessage)
            }
            return true
        } catch {
            guard isCurrentPickedScreenWindowFit(revision) else {
                return false
            }
            if shouldUpdateCapture {
                publishWindowFitMessage(error.localizedDescription)
            }
            return false
        }
    }
}

struct WindowFitAdmission {
    let key: String
    let reason: String
    let origin: WindowFitLoopGuard.Origin
}
