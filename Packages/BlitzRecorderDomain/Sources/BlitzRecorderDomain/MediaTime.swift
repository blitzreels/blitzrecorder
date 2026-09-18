import Foundation

/// Rational media timestamp at a fixed 600 Hz tick rate (same as the Mac `CMTime` maps).
public struct MediaTime: Equatable, Hashable, Sendable, Codable, Comparable {
    public static let timescale: Int32 = 600
    public static let zero = MediaTime(value: 0)

    public var value: Int64

    public init(value: Int64, timescale: Int32 = timescale) {
        if timescale == Self.timescale || timescale == 0 {
            self.value = value
            return
        }
        let numerator = value * Int64(Self.timescale)
        let denominator = Int64(timescale)
        let rounding = numerator >= 0 ? denominator / 2 : -(denominator / 2)
        self.value = (numerator + rounding) / denominator
    }

    public init(seconds: Double, timescale: Int32 = timescale) {
        let ticks = timescale == 0 ? Self.timescale : timescale
        guard seconds.isFinite else {
            self.init(value: 0, timescale: ticks)
            return
        }
        self.init(value: Int64((seconds * Double(ticks)).rounded()), timescale: ticks)
    }

    public var seconds: Double {
        Double(value) / Double(Self.timescale)
    }

    /// Media Foundation / Win32 100-nanosecond units.
    public var hundredNanoseconds: Int64 {
        Int64((seconds * 10_000_000).rounded())
    }

    public init(hundredNanoseconds: Int64) {
        self.init(seconds: Double(hundredNanoseconds) / 10_000_000)
    }

    public static func + (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        MediaTime(value: lhs.value + rhs.value)
    }

    public static func - (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        MediaTime(value: lhs.value - rhs.value)
    }

    public static func < (lhs: MediaTime, rhs: MediaTime) -> Bool {
        lhs.value < rhs.value
    }

    public static func maximum(_ lhs: MediaTime, _ rhs: MediaTime) -> MediaTime {
        lhs.value >= rhs.value ? lhs : rhs
    }

    public static func minimum(_ lhs: MediaTime, _ rhs: MediaTime) -> MediaTime {
        lhs.value <= rhs.value ? lhs : rhs
    }
}
