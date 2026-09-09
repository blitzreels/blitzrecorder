import Foundation
import Observation

@MainActor
@Observable
final class ProjectLibraryTrashController {
    struct Operations {
        let trash: (RecordingProjectDeletionRequest) async throws -> RecordingProjectTrashReceipt?
        let restore: (RecordingProjectRestorationRequest) async throws -> Void

        static let live = Self(
            trash: { request in
                try await Task.detached(priority: .userInitiated) {
                    try TakeFileStore().deleteProject(request)
                }.value
            },
            restore: { request in
                try await Task.detached(priority: .userInitiated) {
                    try TakeFileStore().restoreProjectFromTrash(request)
                }.value
            }
        )
    }

    struct Request {
        let projects: [RecordingProjectHistory.Entry]
        let settings: RecordingSettings
    }

    struct Outcome {
        var completedIDs: Set<UUID> = []
        var failures: [String] = []
    }

    private(set) var isWorking = false
    private(set) var status: String?
    private var batches: [[RecordingProjectRestorationRequest]] = []
    private let operations: Operations

    var restorableCount: Int { batches.last?.count ?? 0 }
    var canRestore: Bool { !isWorking && restorableCount > 0 }

    init(operations: Operations) {
        self.operations = operations
    }

    func trash(_ request: Request) async -> Outcome {
        guard !isWorking else { return Outcome() }
        isWorking = true
        defer { isWorking = false }
        var outcome = Outcome()
        var receipts: [RecordingProjectRestorationRequest] = []
        var seen: Set<UUID> = []
        let projects = request.projects.filter { seen.insert($0.id).inserted }
        for (index, project) in projects.enumerated() {
            status = "Moving to Trash… \(index + 1) of \(projects.count)"
            do {
                if let receipt = try await operations.trash(
                    .init(project: project, settings: request.settings, disposition: .trash))
                {
                    receipts.append(.init(receipt: receipt, settings: request.settings))
                }
                outcome.completedIDs.insert(project.id)
            } catch {
                outcome.failures.append("\(project.displayTitle): \(error.localizedDescription)")
            }
        }
        if !receipts.isEmpty { batches.append(receipts) }
        let count = outcome.completedIDs.count
        status = count == 0 ? nil : "\(count) project\(count == 1 ? "" : "s") moved to Trash"
        return outcome
    }

    func restoreLastBatch() async -> Outcome {
        guard canRestore, let batch = batches.popLast() else { return Outcome() }
        isWorking = true
        defer { isWorking = false }
        var outcome = Outcome()
        var remaining: [RecordingProjectRestorationRequest] = []
        for (index, request) in batch.enumerated() {
            status = "Restoring… \(index + 1) of \(batch.count)"
            do {
                try await operations.restore(request)
                outcome.completedIDs.insert(request.receipt.project.id)
            } catch {
                remaining.append(request)
                outcome.failures.append("\(request.receipt.project.displayTitle): \(error.localizedDescription)")
            }
        }
        if !remaining.isEmpty { batches.append(remaining) }
        let count = outcome.completedIDs.count
        status = count == 0 ? nil : "\(count) project\(count == 1 ? "" : "s") restored"
        return outcome
    }

    func dismissStatus() {
        guard !isWorking else { return }
        status = nil
    }
}
