import AppKit
import BlitzRecorderCore
import Foundation

extension RecorderViewModel {
    var canStartRecording: Bool {
        recordingReadiness.isReady
    }

    func openReadinessDetails() {
        onPresentSettings?(.permissions)
    }

    var dockRecordingBlockerSummary: String? {
        let readiness = recordingReadiness
        guard !readiness.isReady,
              !readiness.blockers.contains(where: { sourceReadinessNotice($0.source) != nil }) else { return nil }
        return readiness.blockers.shortSummary
    }

    var recordingBlockerDetail: String? {
        let readiness = recordingReadiness
        return readiness.isReady ? nil : readiness.detail
    }

    var formattedElapsed: String {
        ClockDuration.elapsedLabel(session.elapsedSeconds)
    }

    var renderProgressLabel: String {
        "\(Int((exports.renderProgress * 100).rounded()))%"
    }

    var sessionProgressTitle: String {
        switch state {
        case .starting:
            return "Getting Ready"
        case .finishing:
            if remoteTransferProgress != nil {
                return "Downloading iPhone Media"
            }
            return session.captureStopProgress?.title ?? finishingMessageTitle ?? "Saving Recording"
        case .recording, .paused:
            return state == .paused ? "Paused" : "Recording"
        case .idle:
            return ""
        }
    }

    var sessionProgressValue: Double? {
        if state == .finishing, let remoteTransferProgress { return remoteTransferProgress.fraction }
        if let captureStopProgress = session.captureStopProgress { return captureStopProgress.fraction }
        if detailMessage.hasPrefix("Exporting") || detailMessage.hasPrefix("Removing camera background") {
            return exports.renderProgress
        }
        return nil
    }

    var sessionProgressLabel: String {
        if state == .finishing,
           let remoteTransferProgress {
            return "\(Int((remoteTransferProgress.fraction * 100).rounded()))%"
        }
        if let captureStopProgress = session.captureStopProgress { return captureStopProgress.label }
        return sessionProgressValue == nil ? "" : renderProgressLabel
    }

    var sessionProgressDetail: String? {
        if state == .starting {
            return sanitizedProgressMessage ?? "Not recording yet. Hang on while BlitzRecorder prepares capture."
        }
        guard state == .finishing else { return nil }
        if let remoteTransferProgress {
            return byteProgressLabel(remoteTransferProgress)
        }
        if let captureStopProgress = session.captureStopProgress { return captureStopProgress.detail }
        return "Your recording is being saved. Keep BlitzRecorder open."
    }

    var sanitizedProgressMessage: String? {
        let message = detailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              !message.hasPrefix("Saved:"),
              !message.hasPrefix("Recording failed:") else {
            return nil
        }
        return message
    }

    var finishingMessageTitle: String? {
        guard let message = sanitizedProgressMessage else { return nil }
        if message.localizedCaseInsensitiveContains("download") ||
            message.localizedCaseInsensitiveContains("iphone") {
            return message
        }
        if message.hasSuffix("...") || message.hasSuffix("…") {
            return String(message.dropLast(message.hasSuffix("...") ? 3 : 1))
        }
        return message
    }
}

/// Readiness asks macOS about screen, camera and microphone access, and views read it many times in one update.
/// One answer serves the rest of the current main run loop turn, unless the permission token or settings change.
@MainActor
final class RecordingReadinessCache {
    struct Request {
        let token: Int
        let make: () -> RecordingReadiness
    }

    private var cached: (token: Int, readiness: RecordingReadiness)?

    func readiness(_ request: Request) -> RecordingReadiness {
        if let cached, cached.token == request.token { return cached.readiness }
        let readiness = request.make()
        if cached == nil {
            DispatchQueue.main.async { [weak self] in self?.cached = nil }
        }
        cached = (request.token, readiness)
        return readiness
    }

    func clear() {
        cached = nil
    }
}
