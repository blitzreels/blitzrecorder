import Foundation

/// Why the chosen iPhone is not connected, as far as this Mac can tell. A sleeping iPhone cannot be asked,
/// so this is what the iPhone said last, or what the Mac saw happen.
enum RemoteCameraAbsence: Equatable {
    /// The iPhone said it was locking or leaving the app.
    case asleep(since: Date)
    /// The connection went quiet without a goodbye: the app quit, or the Wi‑Fi dropped.
    case stoppedResponding(since: Date)
    /// An iPhone this Mac has used before is not on the network now.
    case notFound
    /// No iPhone has connected to this Mac yet.
    case neverConnected

    struct Note: Equatable {
        enum Kind: Equatable {
            case asleep
            case stoppedResponding
        }

        let kind: Kind
        let since: Date
    }

    init(note: Note?, hasConnectedBefore: Bool) {
        guard let note else {
            self = hasConnectedBefore ? .notFound : .neverConnected
            return
        }
        switch note.kind {
        case .asleep: self = .asleep(since: note.since)
        case .stoppedResponding: self = .stoppedResponding(since: note.since)
        }
    }

    /// Short words for the sidebar and status lines.
    var statusLabel: String {
        switch self {
        case .asleep: "iPhone asleep"
        case .stoppedResponding: "Not responding"
        case .notFound, .neverConnected: "Waiting"
        }
    }

    func title(deviceName: String) -> String {
        switch self {
        case .asleep: "\(deviceName) is asleep"
        case .stoppedResponding: "\(deviceName) stopped responding"
        case .notFound, .neverConnected: "Open BlitzRecorder Camera on \(deviceName)"
        }
    }

    var instruction: String {
        switch self {
        case .asleep:
            "Unlock it and open BlitzRecorder Camera. It reconnects by itself."
        case .stoppedResponding:
            "Open BlitzRecorder Camera on it, on the same Wi‑Fi as this Mac. It reconnects by itself."
        case .notFound, .neverConnected:
            "Keep it open on the same Wi‑Fi as this Mac. It connects by itself, and the preview appears here."
        }
    }

    var isAsleep: Bool {
        if case .asleep = self { return true }
        return false
    }

    var lastSeen: Date? {
        switch self {
        case .asleep(let since), .stoppedResponding(let since): since
        case .notFound, .neverConnected: nil
        }
    }
}
