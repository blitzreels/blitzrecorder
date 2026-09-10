import Foundation

struct ScreenWindowIdentity: Hashable {
    let windowID: UInt32
    let processID: Int32?
    let bundleIdentifier: String?

    func matches(_ candidate: Self) -> Bool {
        windowID == candidate.windowID
            && (processID == nil || processID == candidate.processID)
            && (bundleIdentifier == nil || bundleIdentifier == candidate.bundleIdentifier)
    }
}

extension ScreenWindowIdentity {
    init?(_ binding: ScreenSourceBinding) {
        guard binding.kind == .window, let windowID = binding.windowID else { return nil }
        self.init(windowID: windowID, processID: binding.processID, bundleIdentifier: binding.bundleIdentifier)
    }
}

extension ScreenSourceBinding {
    var runtimeID: String {
        switch kind {
        case .display:
            return id
        case .application, .window:
            return "\(id):owner:\(bundleIdentifier ?? ""):pid:\(processID.map(String.init) ?? "unknown")"
        }
    }
}
