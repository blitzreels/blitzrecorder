import Foundation

/// The project list every window shows. It lives on the coordinator, so the main window and the editor window
/// read one list and a refresh started in either updates both.
@MainActor
@Observable
final class ProjectLibraryStore {
    var entries: [RecordingProjectHistory.Entry] = []
    @ObservationIgnored private var refreshTask: Task<[RecordingProjectHistory.Entry], Never>?

    struct RefreshRequest {
        let settings: RecordingSettings
        /// Start a new scan even if one is running, so a write made just before is included.
        let includesLatestWrites: Bool
    }

    /// Reloads off the main thread. A running refresh is joined unless the caller needs its own latest writes.
    @discardableResult
    func refresh(_ request: RefreshRequest) async -> [RecordingProjectHistory.Entry] {
        if let refreshTask, !request.includesLatestWrites { return await refreshTask.value }
        let settings = request.settings
        let task = Task.detached(priority: .utility) {
            TakeFileStore().loadProjectHistory(settings: settings).entries
        }
        refreshTask = task
        let loaded = await task.value
        guard refreshTask == task else { return loaded }
        refreshTask = nil
        if entries != loaded { entries = loaded }
        return loaded
    }

    /// Swaps in the row of one project that is already listed, after a save that only changed that project.
    /// Returns false when it is not listed, so the caller reloads instead.
    func replace(_ entry: RecordingProjectHistory.Entry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        var history = RecordingProjectHistory(version: 1, entries: entries)
        history.entries[index] = entry
        history.sortByRecordedDate()
        entries = history.entries
        return true
    }

    /// Reloads now, for callers that need the list to include a write they just made.
    @discardableResult
    func reload(settings: RecordingSettings) -> [RecordingProjectHistory.Entry] {
        refreshTask?.cancel()
        refreshTask = nil
        entries = TakeFileStore().loadProjectHistory(settings: settings).entries
        return entries
    }
}
