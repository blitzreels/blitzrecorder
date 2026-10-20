import AppKit
import Foundation

extension RecorderViewModel {
    func pickScreen() {
        pickAndEnableScreenSource()
    }
}

extension RecorderViewModel {
    func refreshScreenSuggestion() {
        guard state == .recording, settings.enabledSources.contains(.screen) else {
            screenSource.suggestedScreenSource = nil
            screenSource.dismissedScreenSuggestion = nil
            screenSource.pendingFollowKey = nil
            screenSource.autoSwitchNoticeTask?.cancel()
            screenSource.autoSwitchNotice = nil
            return
        }
        guard !coordinator.isSwitchingScreenSource else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            screenSource.pendingFollowKey = nil
            return
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []
        guard let window = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier
                && RecordingSourceSuggestion.isRecordableWindow($0)
        }), let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
            updateScreenSuggestion(nil)
            return
        }
        let candidate = ScreenSourceBinding(kind: .window, displayID: nil,
            bundleIdentifier: app.bundleIdentifier, applicationName: app.localizedName,
            processID: app.processIdentifier, windowID: windowID,
            windowTitle: window[kCGWindowName as String] as? String)
        updateScreenSuggestion(candidate)
    }

    func updateScreenSuggestion(_ candidate: ScreenSourceBinding?) {
        guard let candidate else {
            screenSource.suggestedScreenSource = nil
            screenSource.dismissedScreenSuggestion = nil
            screenSource.pendingFollowKey = nil
            return
        }
        guard RecordingSourceSuggestion.shouldSuggest(.init(current: settings.screenSourceBinding,
            candidate: candidate, ownProcessID: ProcessInfo.processInfo.processIdentifier)) else {
            screenSource.suggestedScreenSource = nil
            screenSource.dismissedScreenSuggestion = nil
            screenSource.pendingFollowKey = nil
            return
        }
        let key = candidate.id
        if screenSource.suggestedScreenSource?.id != key { screenSource.suggestedScreenSource = nil }
        if screenSource.dismissedScreenSuggestion != key { screenSource.dismissedScreenSuggestion = nil }
        guard screenSource.pendingFollowKey == key else {
            screenSource.pendingFollowKey = key
            return
        }
        guard followsActiveWindow else {
            screenSource.suggestedScreenSource = screenSource.dismissedScreenSuggestion == key ? nil : candidate
            return
        }
        screenSource.suggestedScreenSource = nil
        screenSource.pendingFollowKey = nil
        setScreenSource(candidate)
        showAutoSwitchNotice(candidate)
    }

    private func showAutoSwitchNotice(_ source: ScreenSourceBinding) {
        screenSource.autoSwitchNotice = source
        screenSource.autoSwitchNoticeTask?.cancel()
        screenSource.autoSwitchNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.screenSource.autoSwitchNotice = nil
        }
    }

    func acceptScreenSuggestion() {
        guard let source = screenSource.suggestedScreenSource, state == .recording,
            !coordinator.isSwitchingScreenSource else { return }
        screenSource.suggestedScreenSource = nil
        screenSource.dismissedScreenSuggestion = nil
        screenSource.pendingFollowKey = nil
        setScreenSource(source)
    }

    func dismissScreenSuggestion() {
        guard let source = screenSource.suggestedScreenSource else { return }
        screenSource.dismissedScreenSuggestion = source.id
        screenSource.suggestedScreenSource = nil
    }
}
