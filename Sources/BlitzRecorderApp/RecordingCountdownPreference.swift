import Foundation

struct RecordingCountdownPreference {
    static let key = "recording.countdown.seconds"
    static let options = [0, 3, 5]
    static let defaultSeconds = 3

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var seconds: Int {
        guard defaults.object(forKey: Self.key) != nil else { return Self.defaultSeconds }
        let stored = defaults.integer(forKey: Self.key)
        return Self.options.contains(stored) ? stored : Self.defaultSeconds
    }

    func setSeconds(_ seconds: Int) {
        defaults.set(Self.options.contains(seconds) ? seconds : Self.defaultSeconds, forKey: Self.key)
    }
}
