import Foundation

enum RecordingProjectLibrary {
    static func matching(
        _ projects: [RecordingProjectHistory.Entry],
        query: String
    ) -> [RecordingProjectHistory.Entry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.takeDirectoryPath.localizedCaseInsensitiveContains(query)
        }
    }

    static func shouldClearOpenProject(
        deletedIDs: Set<UUID>,
        deletedTakePaths: Set<String>,
        openProjectID: UUID?,
        openTakePath: String?
    ) -> Bool {
        if let openProjectID, deletedIDs.contains(openProjectID) {
            return true
        }
        if let openTakePath, deletedTakePaths.contains(openTakePath) {
            return true
        }
        return false
    }

    static func trashFailureMessage(_ failures: [String]) -> String? {
        guard !failures.isEmpty else { return nil }
        let remaining = failures.count > 3 ? "\n…and \(failures.count - 3) more." : ""
        return failures.prefix(3).joined(separator: "\n\n") + remaining
    }
}
