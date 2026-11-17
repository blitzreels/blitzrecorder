import AVFoundation
import Foundation

/// After a take, compares every track's length with the time actually recorded: wall clock from the take's start
/// to its stop, minus the pauses, minus the time before the track's first sample. A track that lost or gained time
/// shows here even when its own timestamps look regular.
enum TakeLengthCheck {
    static let toleratedSeconds = 0.25

    struct Track {
        let url: URL
        let mediaType: AVMediaType
        let expectedSeconds: Double
    }

    struct Request {
        let recordedSeconds: Double
        let pausedSeconds: Double
        let tracks: [Track]
    }

    static func run(_ request: Request) async {
        var parts: [String] = []
        var mismatched: [String] = []
        for track in request.tracks {
            let name = track.url.lastPathComponent
            guard let seconds = await MediaFileDuration.playable(.init(url: track.url, mediaType: track.mediaType)) else {
                parts.append("\(name) unreadable")
                mismatched.append(name)
                continue
            }
            let difference = seconds - track.expectedSeconds
            TakeSyncJournal.record(.init(
                trackURL: track.url, kind: .trackLength, at: nil, seconds: difference,
                detail: String(format: "%.2f s of %.2f s", seconds, track.expectedSeconds)
            ))
            parts.append(String(format: "%@ %.2f s (%+.2f)", name, seconds, difference))
            if abs(difference) > toleratedSeconds { mismatched.append(name) }
        }
        guard !parts.isEmpty else { return }
        CaptureLog.note(String(
            format: "Take length check: %.2f s recorded (%.2f s paused); ", request.recordedSeconds, request.pausedSeconds
        ) + parts.joined(separator: ", ")
            + (mismatched.isEmpty ? "; all tracks match" : "; off by more than 0.25 s: " + mismatched.joined(separator: ", ")))
    }
}
