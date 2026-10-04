import Foundation

struct RecordingSessionActiveTake {
    let take: RecordingTake
    let settings: RecordingSettings
}

struct RecordingSessionStopContext {
    let take: RecordingTake?
    let settings: RecordingSettings?
}

@MainActor
final class RecordingSession {
    struct PreparationRequest {
        let outputDirectoryAccess: OutputDirectoryAccess
    }

    private(set) var state: RecordingState = .idle {
        didSet { onStateChanged?(state) }
    }
    private(set) var isExporting = false
    private(set) var lastTake: RecordingTake?
    private var activeTakeSettings: RecordingSettings?
    private var outputDirectoryAccess: OutputDirectoryAccess?

    var onStateChanged: ((RecordingState) -> Void)?

    func beginPreparation(_ request: PreparationRequest) -> Bool {
        guard state == .idle else { return false }
        releaseOutputDirectory()
        outputDirectoryAccess = request.outputDirectoryAccess
        state = .starting
        return true
    }

    func noteActiveTake(_ activeTake: RecordingSessionActiveTake) {
        guard state == .starting else { return }
        lastTake = activeTake.take
        activeTakeSettings = activeTake.settings
    }

    func markRecordingStarted() {
        guard state == .starting, lastTake != nil else { return }
        state = .recording
    }

    func failPreparation() {
        guard state == .starting else { return }
        lastTake = nil
        activeTakeSettings = nil
        releaseOutputDirectory()
        state = .idle
    }

    func pause() -> Bool {
        guard state == .recording else { return false }
        state = .paused
        return true
    }

    func resume() -> Bool {
        guard state == .paused else { return false }
        state = .recording
        return true
    }

    func beginFinishing() -> RecordingSessionStopContext? {
        guard state == .recording || state == .paused else { return nil }
        state = .finishing
        return RecordingSessionStopContext(take: lastTake, settings: activeTakeSettings)
    }

    func finish(with lastTake: RecordingTake?) {
        self.lastTake = lastTake
        activeTakeSettings = nil
        releaseOutputDirectory()
        state = .idle
    }

    func beginExport() -> Bool {
        guard !isExporting else { return false }
        isExporting = true
        return true
    }

    func finishExport() {
        isExporting = false
    }

    func clearLastTake() {
        lastTake = nil
    }

    private func releaseOutputDirectory() {
        outputDirectoryAccess?.stop()
        outputDirectoryAccess = nil
    }
}
