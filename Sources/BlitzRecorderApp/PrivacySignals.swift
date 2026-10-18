import AppKit

struct RecordingPrivacySignal: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case notification
        case passwordManager
    }

    let time: Double
    let kind: Kind
    let app: String
    let windowID: UInt32
    let frame: CGRect
}

struct RecordingPrivacySignalTrack: Codable, Sendable {
    static let fileName = "privacy-signals.json"
    let version: Int
    let signals: [RecordingPrivacySignal]
}

enum SensitiveWindowScanner {
    struct Window {
        let kind: RecordingPrivacySignal.Kind
        let app: String
        let windowID: UInt32
        let bounds: CGRect
    }

    private static let notificationCenter = "com.apple.notificationcenterui"
    private static let passwordManagers: Set<String> = [
        "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password", "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx", "com.bitwarden.desktop", "com.lastpass.LastPass", "org.keepassxc.keepassxc",
        "in.sinew.Enpass-Desktop", "me.proton.pass.electron"
    ]

    static func visibleWindows() -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var bundles: [pid_t: String] = [:]
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width > 40, bounds.height > 20,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { return nil }
            let bundle = bundles[pid] ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            bundles[pid] = bundle
            let kind: RecordingPrivacySignal.Kind
            if bundle == notificationCenter {
                guard (info[kCGWindowLayer as String] as? Int ?? 0) > 0 else { return nil }
                kind = .notification
            } else if passwordManagers.contains(bundle) {
                kind = .passwordManager
            } else { return nil }
            let app = info[kCGWindowOwnerName as String] as? String ?? bundle
            return Window(kind: kind, app: app, windowID: UInt32(truncatingIfNeeded: number), bounds: bounds)
        }
    }
}
