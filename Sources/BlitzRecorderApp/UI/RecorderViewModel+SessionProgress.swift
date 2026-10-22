import AppKit
import BlitzRecorderCore
import Foundation

extension RecorderViewModel {
    var canStartRecording: Bool {
        _ = permissionRefreshToken
        return coordinator.recordingReadiness().isReady
    }

    func openReadinessDetails() {
        onPresentSettings?(.permissions)
    }

    var dockRecordingBlockerSummary: String? {
        _ = permissionRefreshToken
        let readiness = coordinator.recordingReadiness()
        guard !readiness.isReady,
              !readiness.blockers.contains(where: { sourceReadinessNotice($0.source) != nil }) else { return nil }
        return readiness.blockers.shortSummary
    }

    var recordingBlockerDetail: String? {
        let readiness = coordinator.recordingReadiness()
        return readiness.isReady ? nil : readiness.detail
    }

    var formattedElapsed: String {
        let total = session.elapsedSeconds
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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
