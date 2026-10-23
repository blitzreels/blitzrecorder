import Foundation

/// Writes editor changes to disk behind the editor, one at a time and in order, off the main thread. The editor
/// shows a change as soon as it is made, so a slow or network drive delays the write, never the window.
///
/// Until a change is on disk, `pendingProject(at:)` hands it to anyone who reads the project, so an export,
/// a share or another window started in the meantime still sees it.
final class ProjectSaveQueue: @unchecked Sendable {
    static let shared = ProjectSaveQueue()

    struct Save {
        let projectURL: URL
        let project: RecordingProject
        /// The saved revision the change was made on; anything else on disk means someone else saved first.
        let baseRevision: Int
        let settings: RecordingSettings
        let owner: ObjectIdentifier
        let generation: Int
        let completion: @MainActor (Outcome) -> Void
    }

    enum Outcome {
        case saved(RecordingProject)
        /// The owner's later queued changes were dropped; it continues with `generation`.
        case conflict(ProjectEditConflict, generation: Int)
        case failed(Error, saved: RecordingProject?, generation: Int)
        /// Dropped because an earlier change of the same owner could not be saved.
        case skipped
    }

    private struct OwnerProject: Hashable {
        let owner: ObjectIdentifier
        let path: String

        init(owner: ObjectIdentifier, path: String) {
            self.owner = owner
            self.path = path
        }

        init(_ save: Save) {
            self.init(owner: save.owner, path: ProjectSaveQueue.key(for: save.projectURL))
        }
    }

    private struct Pending {
        var count: Int
        var latest: RecordingProject
    }

    private static let queueKey = DispatchSpecificKey<Void>()
    private let queue = DispatchQueue(label: "dev.blitzreels.blitzrecorder.project-saves", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: [String: Pending] = [:]
    private var ownerPending: [OwnerProject: Int] = [:]
    private var generations: [OwnerProject: Int] = [:]

    private init() {
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    static func key(for url: URL) -> String { url.standardizedFileURL.path }

    func enqueue(_ save: Save) {
        let ownerProject = OwnerProject(save)
        lock.withLock {
            pending[ownerProject.path] = Pending(count: (pending[ownerProject.path]?.count ?? 0) + 1, latest: save.project)
            ownerPending[ownerProject, default: 0] += 1
        }
        queue.async {
            let outcome = self.run(save)
            self.markFinished(ownerProject)
            DispatchQueue.main.async { MainActor.assumeIsolated { save.completion(outcome) } }
        }
    }

    private func markFinished(_ ownerProject: OwnerProject) {
        lock.withLock {
            if let count = pending[ownerProject.path]?.count, count > 1 {
                pending[ownerProject.path]?.count = count - 1
            } else {
                pending.removeValue(forKey: ownerProject.path)
            }
            if let count = ownerPending[ownerProject], count > 1 {
                ownerPending[ownerProject] = count - 1
            } else {
                ownerPending.removeValue(forKey: ownerProject)
            }
        }
    }

    /// The newest change still waiting to be written, or nil once the file holds it. The save queue itself always
    /// reads the file.
    func pendingProject(at url: URL) -> RecordingProject? {
        guard DispatchQueue.getSpecific(key: Self.queueKey) == nil else { return nil }
        return lock.withLock { pending[Self.key(for: url)]?.latest }
    }

    func hasPendingSaves(projectPath: String, owner: ObjectIdentifier) -> Bool {
        lock.withLock { ownerPending[OwnerProject(owner: owner, path: Self.key(for: URL(fileURLWithPath: projectPath)))] != nil }
    }

    /// Blocks until every queued change is on disk, for quitting the app.
    func waitUntilIdle() {
        guard DispatchQueue.getSpecific(key: Self.queueKey) == nil else { return }
        queue.sync {}
    }

    private func run(_ save: Save) -> Outcome {
        let ownerProject = OwnerProject(save)
        guard lock.withLock({ generations[ownerProject, default: 0] }) == save.generation else { return .skipped }
        do {
            return .saved(try TakeFileStore().saveStagedProject(save))
        } catch let conflict as ProjectEditConflict {
            return .conflict(conflict, generation: nextGeneration(ownerProject))
        } catch {
            let saved = try? TakeFileStore().loadRecordingProject(at: save.projectURL)
            return .failed(error, saved: saved, generation: nextGeneration(ownerProject))
        }
    }

    /// Later changes from the same owner were made on top of the one that failed, so they are dropped too.
    private func nextGeneration(_ ownerProject: OwnerProject) -> Int {
        lock.withLock {
            generations[ownerProject, default: 0] += 1
            return generations[ownerProject, default: 0]
        }
    }
}
