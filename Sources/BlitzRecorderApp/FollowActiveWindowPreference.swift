import Foundation

struct FollowActiveWindowPreference {
    static let key = "recording.followActiveWindow.enabled"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.key) }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}
