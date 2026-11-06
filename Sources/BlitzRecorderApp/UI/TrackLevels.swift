import Foundation
import Observation

@Observable
@MainActor
final class TrackLevels {
    private(set) var levels: [Float]
    private let capacity: Int
    @ObservationIgnored private var silenceTask: Task<Void, Never>?

    init(capacity: Int = 32) {
        self.capacity = capacity
        self.levels = Array(repeating: 0, count: capacity)
    }

    /// A source that stops sending levels, such as a microphone that stopped delivering, falls silent on the
    /// meter after half a second instead of freezing on its last bars.
    func append(_ level: Float) {
        push(level)
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            while !Task.isCancelled, let self, self.levels.contains(where: { $0 > 0 }) {
                self.push(0)
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    func clear() {
        silenceTask?.cancel()
        levels = Array(repeating: 0, count: capacity)
    }

    private func push(_ level: Float) {
        if levels.count >= capacity {
            levels.removeFirst()
        }
        levels.append(level)
    }

    var peak: Float {
        levels.max() ?? 0
    }

    /// Each level as a share of the loudest sound in the last second, so normal speech fills a meter at any
    /// microphone gain; 0 is silence. Raw levels of speech sit around 0.01–0.3, too small to read on their own.
    var meterFractions: [Float] {
        let reference = max(0.08, (levels.suffix(16).max() ?? 0) * 0.86)
        return levels.map { $0 > 0.003 ? max(0.08, min(1, $0 / reference)) : 0 }
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
