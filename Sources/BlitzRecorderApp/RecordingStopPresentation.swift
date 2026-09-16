import Foundation

enum RecordingStopPresentation {
    enum LiveComposited: Equatable {
        case saved(SavedRecordingOutput)
        case recovery(RecordingRecoveryOutput)
        case noFrames
    }

    static func liveComposited(
        wroteMedia: Bool,
        finalURL: URL?,
        take: RecordingTake?,
        warning: String?
    ) -> LiveComposited {
        if wroteMedia, let finalURL {
            return .saved(SavedRecordingOutput(
                url: finalURL,
                sourceDirectory: nil,
                warning: warning
            ))
        }
        if let take {
            return .recovery(RecordingRecoveryOutput(
                takeDirectory: take.scratchDirectory,
                reason: "No video frames captured",
                canRetryExport: false
            ))
        }
        return .noFrames
    }

    static func shouldCleanupTakeFiles(_ live: LiveComposited) -> Bool {
        if case .saved = live { return true }
        return false
    }

    enum Finalization {
        case project(PostRecordingProjectOutput)
        case saved(SavedRecordingOutput)
        case recovery(RecordingRecoveryOutput)
        case message(String)
    }

    static func finalization(
        outcome: TakeFinalizationOutcome,
        activeCaptureWarning: String?,
        savedRecordingStopWarning: String?,
        stopFailureWarning: String?,
        settings: RecordingSettings
    ) -> Finalization {
        switch outcome {
        case .projectReady, .projectReadyWithWarning:
            let warning = RecordingWarning.combined([activeCaptureWarning, savedRecordingStopWarning])
            if let projectOutput = outcome.projectOutput(warning: warning) {
                return .project(projectOutput)
            }
            return .message(outcome.userMessage)
        case .saved:
            let warning = RecordingWarning.combined([activeCaptureWarning, savedRecordingStopWarning])
            if let savedOutput = outcome.savedOutput(warning: warning) {
                return .saved(savedOutput)
            }
            return .message(outcome.userMessage)
        case .recoveryFiles:
            let recoveryReason = outcome.recoveryReason(
                stopWarning: stopFailureWarning,
                settings: settings
            )
            if let recovery = outcome.recoveryOutput(reason: recoveryReason) {
                return .recovery(recovery)
            }
            return .message(RecordingStopCopy.recovery(outcome.userMessage))
        }
    }
}
