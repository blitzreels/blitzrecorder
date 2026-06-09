import Foundation

enum IdlePreviewRestartPolicy {
    static let postFinishingDelayNanoseconds: UInt64 = 500_000_000

    static func delayNanoseconds(
        previousState: RecordingState,
        newState: RecordingState
    ) -> UInt64 {
        previousState == .finishing && newState == .idle
            ? postFinishingDelayNanoseconds
            : 0
    }
}
