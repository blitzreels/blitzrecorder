import Foundation

enum RecordingExportCopy {
    static let waitForRecording = "Wait for the current recording task to finish before exporting."

    static func exporting(_ format: OutputVideoFormat) -> String {
        "Exporting \(format.displayName)..."
    }

    static func failed(_ error: Error) -> String {
        "Project export failed: \(error.recorderFailureDescription)"
    }
}
