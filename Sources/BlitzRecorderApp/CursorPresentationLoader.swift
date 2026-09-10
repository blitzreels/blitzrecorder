import Foundation

actor CursorPresentationLoader {
    static let shared = CursorPresentationLoader()

    private struct Key: Equatable {
        let file: MediaFileFingerprint
        let trimOffset: Double
    }

    private var key: Key?
    private var task: Task<CursorPresentationTrack, Never>?

    func load(_ request: CursorPresentationTrack.LoadRequest) async -> CursorPresentationTrack {
        guard !Task.isCancelled,
              let file = MediaFileFingerprint(url: request.directory.appendingPathComponent("cursor-track.json"))
        else { return .empty }
        let incoming = Key(file: file, trimOffset: request.trimOffset)
        if key == incoming, let task { return await task.value }
        task?.cancel()
        let task = Task.detached(priority: .userInitiated) { CursorPresentationTrack.load(request) }
        key = incoming
        self.task = task
        return await task.value
    }
}
