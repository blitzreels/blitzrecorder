import Foundation
import Observation

@Observable
@MainActor
final class TrackLevels {
    private(set) var levels: [Float]
    private let capacity: Int

    init(capacity: Int = 32) {
        self.capacity = capacity
        self.levels = Array(repeating: 0, count: capacity)
    }

    func append(_ level: Float) {
        if levels.count >= capacity {
            levels.removeFirst()
        }
        levels.append(level)
    }

    func clear() {
        levels = Array(repeating: 0, count: capacity)
    }

    var peak: Float {
        levels.max() ?? 0
    }
}

/// Live levels of the extra microphones, by device.
@Observable
@MainActor
final class MicrophoneTrackLevelStore {
    private(set) var levelsByDeviceID: [String: TrackLevels] = [:]

    func append(_ level: Float, deviceID: String) {
        let levels = levelsByDeviceID[deviceID] ?? TrackLevels()
        if levelsByDeviceID[deviceID] == nil { levelsByDeviceID[deviceID] = levels }
        levels.append(level)
    }
}
