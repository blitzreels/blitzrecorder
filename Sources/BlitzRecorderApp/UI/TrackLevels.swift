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

    var peak: Float {
        levels.max() ?? 0
    }
}
