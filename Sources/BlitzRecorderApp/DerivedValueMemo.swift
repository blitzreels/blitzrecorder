import Foundation

/// Remembers one derived value and works it out again only when its key changes. Views read derived lists many
/// times per update; the key, built from cheap revision numbers, decides whether the work runs at all.
@MainActor
final class DerivedValueMemo<Key: Equatable, Value> {
    struct Request {
        let key: Key
        let make: () -> Value
    }

    private var cached: (key: Key, value: Value)?

    func value(_ request: Request) -> Value {
        if let cached, cached.key == request.key { return cached.value }
        let value = request.make()
        cached = (request.key, value)
        return value
    }
}

/// The library lists every window derives from the shared project list, kept per view model.
@MainActor
final class ProjectLibraryMemos {
    struct FolderKey: Equatable {
        let entriesRevision: Int
        let pinsRevision: Int
    }

    struct SearchKey: Equatable {
        let entriesRevision: Int
        let query: String
    }

    let folderIndex = DerivedValueMemo<FolderKey, ProjectFolderIndex>()
    let folderTree = DerivedValueMemo<FolderKey, [ProjectFolderTree.Node]>()
    let search = DerivedValueMemo<SearchKey, [RecordingProjectHistory.Entry]>()
}
