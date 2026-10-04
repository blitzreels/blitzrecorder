import CoreGraphics

struct AspectRatioStabilizer {
    static let requiredFrames = 8
    static let tolerance: CGFloat = 0.002

    private(set) var stable: CGFloat?
    private var candidate: CGFloat?
    private var candidateFrames = 0

    mutating func feed(_ value: CGFloat) -> CGFloat {
        guard value > 0, value.isFinite else { return stable ?? value }
        guard let current = stable else {
            stable = value
            return value
        }
        if abs(value - current) <= Self.tolerance {
            candidate = nil
            candidateFrames = 0
            return current
        }
        if let pending = candidate, abs(pending - value) <= Self.tolerance {
            candidateFrames += 1
        } else {
            candidate = value
            candidateFrames = 1
        }
        guard candidateFrames >= Self.requiredFrames else { return current }
        stable = value
        candidate = nil
        candidateFrames = 0
        return value
    }

    mutating func reset() {
        stable = nil
        candidate = nil
        candidateFrames = 0
    }
}
