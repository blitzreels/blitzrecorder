import Foundation
import CoreMedia

struct CaptureSourceRunSummary {
    var completions: [CaptureSource: MediaWriterCompletion]
    let stopFailures: [CaptureSource: String]
    let synchronizationFailures: Set<CaptureSource>
    let timelineTrimOffset: CMTime
    var sourceTimelineOffsets: [CaptureSource: CMTime]
    /// One line per extra camera angle that did not save video, such as "Camera 2: …".
    var cameraAngleFailures: [String] = []
    /// One line per extra microphone that did not save audio, or a line when the microphones could not be mixed.
    var microphoneTrackFailures: [String] = []

    init(
        completions: [CaptureSource: MediaWriterCompletion],
        stopFailures: [CaptureSource: String] = [:],
        synchronizationFailures: Set<CaptureSource> = [],
        timelineTrimOffset: CMTime = .zero,
        sourceTimelineOffsets: [CaptureSource: CMTime] = [:]
    ) {
        self.completions = completions
        self.stopFailures = stopFailures
        self.synchronizationFailures = synchronizationFailures
        self.timelineTrimOffset = timelineTrimOffset
        self.sourceTimelineOffsets = sourceTimelineOffsets
    }

    var hasVideoMedia: Bool {
        completions[.screen]?.wroteMedia == true || completions[.camera]?.wroteMedia == true
    }

    var stopFailureWarning: String? {
        RecordingWarning.combined([
            stopFailureWarning(for: Set(CaptureSource.allCases)), cameraAngleWarning, microphoneTrackWarning
        ])
    }

    private var microphoneTrackWarning: String? {
        guard !microphoneTrackFailures.isEmpty else { return nil }
        return "Some microphones were not saved: \(microphoneTrackFailures.joined(separator: "; "))"
    }

    private var cameraAngleWarning: String? {
        guard !cameraAngleFailures.isEmpty else { return nil }
        return "Some camera angles were not saved: \(cameraAngleFailures.joined(separator: "; "))"
    }

    var savedRecordingStopWarning: String? {
        if let videoWarning = stopFailureWarning(for: [.screen, .camera]) {
            return videoWarning
        }
        if let extraTrackWarning = RecordingWarning.combined([cameraAngleWarning, microphoneTrackWarning]) {
            return extraTrackWarning
        }

        let synchronizationFailureNames = [CaptureSource.microphone, .systemAudio]
            .filter { synchronizationFailures.contains($0) }
            .map(\.rawValue)
            .joined(separator: " and ")
        if !synchronizationFailureNames.isEmpty {
            return "\(synchronizationFailureNames) timing could not be corrected. Saved video is intact, but that audio may drift."
        }

        let failedAudioSources = [CaptureSource.microphone, .systemAudio].filter {
            stopFailures[$0] != nil && completions[$0]?.wroteMedia != true
        }
        guard !failedAudioSources.isEmpty else { return nil }
        let names = failedAudioSources.map(\.rawValue).joined(separator: " and ")
        return "\(names) audio could not be finalized. Saved video is intact, but that audio track may be missing."
    }

    private func stopFailureWarning(for sources: Set<CaptureSource>) -> String? {
        let failures = CaptureSource.allCases.compactMap { source -> String? in
            guard sources.contains(source) else { return nil }
            guard let reason = stopFailures[source] else { return nil }
            return "\(source.rawValue): \(Self.userFacingStopFailureReason(for: source, reason: reason))"
        }
        guard !failures.isEmpty else { return nil }
        return "Some sources stopped with errors: \(failures.joined(separator: "; "))"
    }

    private static func userFacingStopFailureReason(for source: CaptureSource, reason: String) -> String {
        let lowercased = reason.lowercased()
        if source == .camera,
           lowercased.contains("remote iphone"),
           lowercased.contains("no video frames captured") {
            return "iPhone camera did not save usable video. Keep BlitzRecorder Camera open until recording stops, then retry."
        }
        if lowercased.contains("no video frames captured") {
            return "No video was captured from this source."
        }
        if lowercased.contains("cannot open") || lowercased.contains("operation not permitted") {
            return "BlitzRecorder could not open the saved media. Check recording-folder permission, then retry."
        }
        return reason
    }
}

struct CaptureSourceStopFailure: Error {
    let completion: MediaWriterCompletion
    let underlyingError: Error
}

struct CaptureSourceRetargetFailure: Error {
    let rollbackFailed: Bool
    let underlyingError: Error

    static func shouldStopTake(for error: Error) -> Bool {
        (error as? CaptureSourceRetargetFailure)?.rollbackFailed == true
    }
}

struct CaptureSourceRunStartResult: Equatable {
    let hostTimelineStartTime: UInt64
    let timelineStartTime: CMTime

    static func == (lhs: CaptureSourceRunStartResult, rhs: CaptureSourceRunStartResult) -> Bool {
        lhs.hostTimelineStartTime == rhs.hostTimelineStartTime
            && CMTimeCompare(lhs.timelineStartTime, rhs.timelineStartTime) == 0
    }
}
