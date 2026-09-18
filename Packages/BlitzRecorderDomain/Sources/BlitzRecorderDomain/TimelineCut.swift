import Foundation

public enum TimelineCutKind: String, Codable, Equatable, Sendable {
    case silence
    case manual
}

public enum TimelineCutSource: String, Codable, Equatable, Sendable {
    case automatic = "auto"
    case user
}

public struct TimelineCut: Equatable, Identifiable, Sendable, Codable {
    public let id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var kind: TimelineCutKind
    public var source: TimelineCutSource
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        kind: TimelineCutKind,
        source: TimelineCutSource,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.source = source
        self.isEnabled = isEnabled
    }

    public var duration: TimeInterval {
        max(0, end - start)
    }
}
