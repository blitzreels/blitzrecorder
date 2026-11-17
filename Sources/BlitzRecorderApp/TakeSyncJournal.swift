import Foundation

/// What happened to each track's timing while a take recorded and when it was saved, kept in the take folder as
/// one JSON line per event, so the library can say whether the recording stayed in sync and what was repaired.
enum TakeSyncJournal {
    static let fileName = "sync-events.jsonl"

    struct Event: Codable, Equatable {
        enum Kind: String, Codable {
            /// The audio file was built from its timestamped backup, the usual end of a take.
            case audioBuilt
            /// The audio file had lost sound and was rebuilt from the backup, with silence where sound was lost.
            case audioRebuilt
            /// The backup missed audio itself, so the writer's file was kept as it was.
            case audioKept
            case audioRebuildFailed
            /// The source delivered nothing for `seconds` at `at` on the take timeline.
            case audioGap
            /// Video timestamps fell `seconds` behind real time; later frames were moved back to their capture time.
            case clockSlip
            /// A camera sent no frames for `seconds`; the last picture was held.
            case frameHole
            /// System audio had to start a new stream for a new app.
            case systemAudioRestarted
            /// `seconds` is how much longer (positive) or shorter the track is than the recorded time.
            case trackLength
            /// The sync test measured the track `seconds` behind the screen; `detail` says why when it is out of sync.
            case syncTest
        }

        let track: String
        let kind: Kind
        /// Seconds on the take timeline where it happened, when known.
        let at: Double?
        let seconds: Double?
        let detail: String?
    }

    /// An event for the track recorded at `trackURL`, which sits in its take folder.
    struct TrackEvent {
        let trackURL: URL
        let kind: Event.Kind
        let at: Double?
        let seconds: Double?
        let detail: String?
    }

    private static let queue = DispatchQueue(label: "blitzrecorder.take-sync-journal", qos: .utility)

    /// Appends the event, only while the take folder exists: a deleted recording stays deleted.
    static func record(_ entry: TrackEvent) {
        let event = Event(track: entry.trackURL.lastPathComponent, kind: entry.kind, at: entry.at,
                          seconds: entry.seconds, detail: entry.detail)
        guard let line = try? JSONEncoder().encode(event) else { return }
        let takeDirectory = entry.trackURL.deletingLastPathComponent()
        queue.async {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: takeDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return }
            let url = takeDirectory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line + Data("\n".utf8))
        }
    }

    /// Waits for every event recorded so far to reach the disk.
    static func flush() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    static func events(in takeDirectory: URL) -> [Event] {
        guard let data = try? Data(contentsOf: takeDirectory.appendingPathComponent(fileName)) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? JSONDecoder().decode(Event.self, from: $0) }
    }
}

/// The sync report shown with a recording: one plain line per thing that went wrong or was repaired.
struct TakeSyncReport: Equatable {
    struct Line: Equatable {
        let text: String
        /// Still off in the saved recording, as opposed to something already repaired.
        let isOpen: Bool
    }

    let lines: [Line]
    /// True when the take was checked and every track matched.
    let isInSync: Bool

    init(events: [TakeSyncJournal.Event]) {
        var lines: [Line] = []
        for event in events {
            let name = Self.trackName(event.track)
            let outcome = events.last { $0.track == event.track && Self.audioOutcomes.contains($0.kind) }?.kind
            switch event.kind {
            case .audioGap:
                let repaired = outcome == .audioBuilt || outcome == .audioRebuilt
                lines.append(.init(
                    text: "\(name) had no sound for \(Self.seconds(event.seconds))\(Self.at(event.at))"
                        + (repaired ? "; silence fills the gap, so it stays in sync" : " and may play early after it"),
                    isOpen: !repaired
                ))
            case .audioRebuilt:
                guard !events.contains(where: { $0.track == event.track && $0.kind == .audioGap }) else { continue }
                lines.append(.init(text: "\(name) was incomplete and was rebuilt from its backup", isOpen: false))
            case .audioRebuildFailed:
                lines.append(.init(text: "\(name) could not be rebuilt from its backup", isOpen: true))
            case .clockSlip:
                lines.append(.init(
                    text: "\(name) fell \(Self.seconds(event.seconds)) behind\(Self.at(event.at)) "
                        + "and was moved back to the time it was filmed",
                    isOpen: false
                ))
            case .frameHole:
                lines.append(.init(
                    text: "\(name) sent no picture for \(Self.seconds(event.seconds))\(Self.at(event.at)); "
                        + "the last picture was held",
                    isOpen: false
                ))
            case .trackLength:
                guard let seconds = event.seconds, abs(seconds) > TakeLengthCheck.toleratedSeconds else { continue }
                lines.append(.init(
                    text: "\(name) is \(Self.seconds(abs(seconds))) \(seconds > 0 ? "longer" : "shorter") than the recording",
                    isOpen: true
                ))
            case .syncTest:
                lines.append(event.detail.map { .init(text: $0, isOpen: true) }
                    ?? .init(text: "\(name) passed the sync test", isOpen: false))
            case .audioBuilt, .audioKept, .systemAudioRestarted:
                continue
            }
        }
        self.lines = lines
        isInSync = events.contains { $0.kind == .trackLength } && !lines.contains(where: \.isOpen)
    }

    private static let audioOutcomes: Set<TakeSyncJournal.Event.Kind> = [
        .audioBuilt, .audioRebuilt, .audioKept, .audioRebuildFailed,
    ]

    var hasContent: Bool { !lines.isEmpty || isInSync }

    static func trackName(_ fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        if base.hasPrefix("system-audio") { return "System audio" }
        if base.hasPrefix("audio") || base.hasPrefix("microphone") { return "Microphone" }
        if base.hasPrefix("camera") { return "Camera" }
        if base.hasPrefix("screen") { return "Screen" }
        return fileName
    }

    private static func seconds(_ value: Double?) -> String {
        String(format: "%.2f s", value ?? 0)
    }

    private static func at(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        let total = Int(value.rounded(.down))
        return String(format: " at %d:%02d", total / 60, total % 60)
    }
}
