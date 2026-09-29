import AppKit
import CoreGraphics
import Foundation

enum ShortsWindowArrangerError: LocalizedError {
    case accessibilityPermissionRequired
    case displayUnavailable
    case noWindowFound
    case windowListUnavailable
    case windowMoveFailed
    case windowNotResizable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Allow BlitzRecorder in Accessibility, then try again."
        case .displayUnavailable:
            return "Selected display is not available."
        case .noWindowFound:
            return "No other window found to fit."
        case .windowListUnavailable:
            return "Could not read the visible window list."
        case .windowMoveFailed:
            return "Could not move the target window."
        case .windowNotResizable:
            return "This app does not allow window resizing. Use Adjust crop instead."
        }
    }
}

enum ScreenWindowFitRetry {
    static let maximumAttempts = 3

    static func run<Value>(_ operation: () async throws -> Value) async throws -> Value {
        for attempt in 1...maximumAttempts {
            do {
                return try await operation()
            } catch ShortsWindowArrangerError.windowMoveFailed where attempt < maximumAttempts {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        throw ShortsWindowArrangerError.windowMoveFailed
    }
}

@MainActor
enum WindowFrameWriter {
    static let settlingInterval: Duration = .milliseconds(10)
    static let maximumSettlingPolls = 50
    static let stableChangedFramePolls = 6

    enum Change {
        case size(CGSize)
        case position(CGPoint)

        func matches(_ frame: CGRect) -> Bool {
            switch self {
            case .size(let size):
                return abs(frame.width - size.width) <= 1 && abs(frame.height - size.height) <= 1
            case .position(let position):
                return abs(frame.minX - position.x) <= 1 && abs(frame.minY - position.y) <= 1
            }
        }
    }

    struct Request {
        let frame: CGRect
        let write: (Change) throws -> Void
        let settle: () async throws -> Void
        let read: () throws -> CGRect
    }

    static func apply(_ request: Request) async throws -> CGRect {
        let changes: [Change] = [
            .size(request.frame.size),
            .position(request.frame.origin),
            .size(request.frame.size)
        ]
        var moved = false
        for (index, change) in changes.enumerated() {
            try Task.checkCancellation()
            if index == 2, !moved { continue }
            let original = try request.read()
            if change.matches(original) { continue }
            try request.write(change)
            var previous = original
            var stablePolls = 0
            var hasChanged = false
            for _ in 0..<maximumSettlingPolls {
                let current = try request.read()
                if change.matches(current) { break }
                hasChanged = hasChanged || current != original
                stablePolls = current == previous ? stablePolls + 1 : 0
                if hasChanged, stablePolls >= stableChangedFramePolls { break }
                previous = current
                try await request.settle()
                try Task.checkCancellation()
            }
            if case .position = change {
                moved = try request.read().origin != original.origin
            }
        }
        return try request.read()
    }
}

struct ShortsWindowArrangement {
    let appName: String
    let windowTitle: String?
    let frame: CGRect
    let screenCrop: CGRect
    var fittedZoom: CGFloat? = nil

    private var displayName: String {
        windowTitle?.isEmpty == false ? "\(appName) - \(windowTitle!)" : appName
    }

    var message: String {
        "Fitted \(displayName) and aligned screen capture."
    }

    var resizedMessage: String {
        "Resized \(displayName) to \(Int(frame.width))x\(Int(frame.height))."
    }

    var screenItemMessage: String {
        "Screen item now shows \(displayName)."
    }
}

struct TargetWindowInfo: Equatable {
    let processID: pid_t?
    let appName: String
    let windowTitle: String?
    let frame: CGRect

    var title: String {
        appName
    }

    var detail: String {
        if let windowTitle, !windowTitle.isEmpty {
            return windowTitle
        }
        return "\(Int(frame.width))x\(Int(frame.height))"
    }

    init(processID: pid_t? = nil, appName: String, windowTitle: String?, frame: CGRect) {
        self.processID = processID
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
    }
}

struct AppWindowSelectionCandidate: Equatable {
    let id: Int
    let frame: CGRect
    let isStandard: Bool

    var area: CGFloat {
        frame.width * frame.height
    }

    var isUsablePrimary: Bool {
        frame.width >= 320 && frame.height >= 220 && area > 0
    }
}

enum AppWindowSelection {
    static func primary(
        from candidates: [AppWindowSelectionCandidate],
        focusedID: Int?,
        mainID: Int?
    ) -> AppWindowSelectionCandidate? {
        let validCandidates = candidates.filter { $0.area > 0 }
        let standardCandidates = validCandidates.filter(\.isStandard)
        let pool = standardCandidates.isEmpty ? validCandidates : standardCandidates

        if let focused = candidate(with: focusedID, in: pool), focused.isUsablePrimary {
            return focused
        }
        if let main = candidate(with: mainID, in: pool), main.isUsablePrimary {
            return main
        }
        return pool.max(by: { $0.area < $1.area })
    }

    private static func candidate(
        with id: Int?,
        in candidates: [AppWindowSelectionCandidate]
    ) -> AppWindowSelectionCandidate? {
        guard let id else { return nil }
        return candidates.first { $0.id == id }
    }
}
