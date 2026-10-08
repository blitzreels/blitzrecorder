import Foundation
import os

let layoutLog = Logger(subsystem: "dev.blitzreels.blitzrecorder", category: "layout")

struct WindowFitLoopGuard {
    static let interval: TimeInterval = 12
    static let limit = 4

    enum Decision: Equatable {
        case allow
        case pauseNow
        case paused
    }

    struct Request {
        let key: String
        let now: Date
        let origin: Origin
    }

    enum Origin {
        case automatic
        case userInitiated
    }

    private var attempts: [String: [Date]] = [:]
    private var pausedKeys: Set<String> = []

    mutating func admit(_ request: Request) -> Decision {
        if request.origin == .userInitiated {
            attempts[request.key] = nil
            pausedKeys.remove(request.key)
            return .allow
        }
        guard !pausedKeys.contains(request.key) else { return .paused }
        let recent = (attempts[request.key] ?? []).filter { request.now.timeIntervalSince($0) < Self.interval }
        guard recent.count < Self.limit else {
            pausedKeys.insert(request.key)
            attempts[request.key] = nil
            return .pauseNow
        }
        attempts[request.key] = recent + [request.now]
        return .allow
    }

    mutating func reset() {
        attempts = [:]
        pausedKeys = []
    }
}
