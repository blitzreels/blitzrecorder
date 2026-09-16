import Foundation

@MainActor
final class ActiveScreenCaptureReconfiguration {
    var configurationRevision = 0
    var configurationTask: Task<Void, Never>?
    var pickerTransactionTask: Task<Void, Never>?
    var pickerTransactionID: UUID?
    var pickerQueuedRevision = 0

    func nextConfigurationGeneration() -> Int {
        configurationRevision += 1
        return configurationRevision
    }

    func queuePickerConfigurationIfNeeded() -> Int? {
        guard pickerTransactionTask != nil else { return nil }
        pickerQueuedRevision += 1
        return pickerQueuedRevision
    }

    func cancelConfiguration() {
        configurationRevision += 1
        configurationTask?.cancel()
        configurationTask = nil
    }

    func shouldApply(generation: Int, state: RecordingState) -> Bool {
        !Task.isCancelled
            && configurationRevision == generation
            && (state == .recording || state == .paused || state == .finishing)
    }

    func isCurrentConfiguration(_ generation: Int) -> Bool {
        configurationRevision == generation
    }

    func isStalePickerQueuedRevision(_ queued: Int?) -> Bool {
        ScreenCaptureGeometry.isStalePickerQueuedRevision(
            queued,
            current: pickerQueuedRevision
        )
    }

    func beginPickerTransaction() -> UUID {
        let transactionID = UUID()
        pickerTransactionID = transactionID
        return transactionID
    }

    func endPickerTransactionIfCurrent(_ transactionID: UUID) {
        guard pickerTransactionID == transactionID else { return }
        pickerTransactionID = nil
        pickerTransactionTask = nil
    }
}
