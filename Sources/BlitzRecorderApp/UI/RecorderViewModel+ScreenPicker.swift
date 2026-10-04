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
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []
        guard let window = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }), let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
            suggestedScreenSource = nil
            return
        }
        let candidate = ScreenSourceBinding(kind: .window, displayID: nil,
            bundleIdentifier: app.bundleIdentifier, applicationName: app.localizedName,
            processID: app.processIdentifier, windowID: windowID,
            windowTitle: window[kCGWindowName as String] as? String)
        guard RecordingSourceSuggestion.shouldSuggest(.init(current: settings.screenSourceBinding,
            candidate: candidate, ownProcessID: ProcessInfo.processInfo.processIdentifier)) else {
            suggestedScreenSource = nil
            dismissedScreenSuggestion = nil
            pendingFollowKey = nil
            return
        }
        let key = candidate.id + (candidate.windowTitle ?? "")
        guard followsActiveWindow else {
            if dismissedScreenSuggestion != key { suggestedScreenSource = candidate }
            return
        }
        suggestedScreenSource = nil
        guard pendingFollowKey == key else {
            pendingFollowKey = key
            return
        }
        pendingFollowKey = nil
        setScreenSource(candidate)
        showAutoSwitchNotice("Now recording \(candidate.applicationName ?? candidate.displayName)")
    }

    private func showAutoSwitchNotice(_ message: String) {
        autoSwitchNotice = message
        autoSwitchNoticeTask?.cancel()
        autoSwitchNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.autoSwitchNotice = nil
        }
    }

    func acceptScreenSuggestion() {
        guard let source = suggestedScreenSource, state == .recording else { return }
        suggestedScreenSource = nil
        dismissedScreenSuggestion = nil
        setScreenSource(source)
    }

    func dismissScreenSuggestion() {
        guard let source = suggestedScreenSource else { return }
        dismissedScreenSuggestion = source.id + (source.windowTitle ?? "")
        suggestedScreenSource = nil
    }
}
