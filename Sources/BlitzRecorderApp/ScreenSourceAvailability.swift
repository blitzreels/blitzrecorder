import AppKit

struct ScreenSourceAvailabilityTracker {
    struct Update {
        let binding: ScreenSourceBinding
        let isPresent: Bool
        let now: Date
    }

    private var sourceID: String?
    private var missingSince: Date?

    mutating func unavailableSource(_ update: Update) -> ScreenSourceBinding? {
        if sourceID != update.binding.runtimeID {
            sourceID = update.binding.runtimeID
            missingSince = nil
        }
        if update.isPresent {
            missingSince = nil
            return nil
        }
        guard let missingSince else {
            missingSince = update.now
            return nil
        }
        return update.now.timeIntervalSince(missingSince) >= 2 ? update.binding : nil
    }
}

struct ScreenSourceWindowPresence {
    let binding: ScreenSourceBinding
    let windows: [[String: Any]]

    var isPresent: Bool {
        guard binding.windowID != nil || binding.windowTitle?.isEmpty == false else { return true }
        return windows.contains { window in
            if let processID = binding.processID,
               (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != processID { return false }
            if let windowID = binding.windowID {
                return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
            }
            return window[kCGWindowName as String] as? String == binding.windowTitle
                && window[kCGWindowOwnerName as String] as? String == binding.applicationName
        }
    }
}

extension RecorderViewModel {
    var unavailableScreenSourceNotice: SourceReadinessNotice? {
        guard isSourceConfigured(.screen), let missing = unavailableScreenSource,
              missing.runtimeID == settings.screenSourceBinding?.runtimeID else { return nil }
        let name = switch missing.kind {
        case .window: "Window"
        case .application: "App"
        case .display: "Display"
        }
        return .init(title: "\(name) unavailable",
                     detail: "\(missing.displayName) is no longer available. Choose another screen source.",
                     action: .chooseScreen, isWaiting: false, severity: .error)
    }

    func refreshScreenSourceAvailability() {
        guard isSourceConfigured(.screen), let binding = settings.screenSourceBinding else {
            screenSourceAvailabilityTracker = ScreenSourceAvailabilityTracker()
            unavailableScreenSource = nil
            return
        }
        let isPresent: Bool
        switch binding.kind {
        case .window:
            guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return }
            isPresent = ScreenSourceWindowPresence(binding: binding, windows: windows).isPresent
        case .application:
            isPresent = ScreenWindowFit.processID(forApplicationBinding: binding) != nil
        case .display:
            guard let displayID = binding.displayID.flatMap(UInt32.init) else {
                screenSourceAvailabilityTracker = ScreenSourceAvailabilityTracker()
                unavailableScreenSource = nil
                return
            }
            isPresent = CGDisplayIsOnline(displayID) != 0
        }
        unavailableScreenSource = screenSourceAvailabilityTracker.unavailableSource(.init(
            binding: binding, isPresent: isPresent, now: Date()
        ))
    }
}
