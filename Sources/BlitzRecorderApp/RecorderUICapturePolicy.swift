import Foundation

struct RecorderUICapturePolicy {
    let includesRecorderUI: Bool
    var ownProcessID: pid_t = getpid()

    func excludes(processID: pid_t?) -> Bool {
        !includesRecorderUI && processID == ownProcessID
    }

    func excludedBundleIDs(_ bundleIdentifier: String?) -> [String] {
        includesRecorderUI ? [] : [bundleIdentifier].compactMap { $0 }
    }
}
