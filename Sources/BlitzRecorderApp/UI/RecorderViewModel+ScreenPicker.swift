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
            suggestedScreenSource = nil
            dismissedScreenSuggestion = nil
            pendingFollowKey = nil
            autoSwitchNoticeTask?.cancel()
            autoSwitchNotice = nil
            return
        }
        guard !coordinator.isSwitchingScreenSource else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            pendingFollowKey = nil
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
            suggestedScreenSource = nil
            dismissedScreenSuggestion = nil
            pendingFollowKey = nil
            return
        }
        guard RecordingSourceSuggestion.shouldSuggest(.init(current: settings.screenSourceBinding,
            candidate: candidate, ownProcessID: ProcessInfo.processInfo.processIdentifier)) else {
            suggestedScreenSource = nil
            dismissedScreenSuggestion = nil
            pendingFollowKey = nil
            return
        }
        let key = candidate.id
        if suggestedScreenSource?.id != key { suggestedScreenSource = nil }
        if dismissedScreenSuggestion != key { dismissedScreenSuggestion = nil }
        guard pendingFollowKey == key else {
            pendingFollowKey = key
            return
        }
        guard followsActiveWindow else {
            suggestedScreenSource = dismissedScreenSuggestion == key ? nil : candidate
            return
        }
        suggestedScreenSource = nil
        pendingFollowKey = nil
        setScreenSource(candidate)
        showAutoSwitchNotice(candidate)
    }

    private func showAutoSwitchNotice(_ source: ScreenSourceBinding) {
        autoSwitchNotice = source
        autoSwitchNoticeTask?.cancel()
        autoSwitchNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.autoSwitchNotice = nil
        }
    }

    func acceptScreenSuggestion() {
        guard let source = suggestedScreenSource, state == .recording,
            !coordinator.isSwitchingScreenSource else { return }
        suggestedScreenSource = nil
        dismissedScreenSuggestion = nil
        pendingFollowKey = nil
        setScreenSource(source)
    }

    func dismissScreenSuggestion() {
        guard let source = suggestedScreenSource else { return }
        dismissedScreenSuggestion = source.id
        suggestedScreenSource = nil
    }
}
