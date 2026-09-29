import Foundation

struct RecordingProjectHistory: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let id: UUID
        let title: String
        let projectPath: String
        let takeDirectoryPath: String
        let finalVideoPath: String?
        let createdAt: Date?
        let updatedAt: Date
        let exports: [RecordingProject.ExportRecord]?
    }

    let version: Int
    var entries: [Entry]
}

enum RecordingProjectDisplayTitle {
    static func isUntitled(_ rawTitle: String) -> Bool {
        timestampDate(from: rawTitle) != nil
    }

    static func make(rawTitle: String, createdAt: Date) -> String {
        guard isUntitled(rawTitle) else { return rawTitle }
        return "Recording at \(createdAt.formatted(date: .omitted, time: .shortened))"
    }

    static func timestampDate(from rawTitle: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter.date(from: String(rawTitle.prefix(19)))
    }
}

extension RecordingProject {
    var displayTitle: String {
        RecordingProjectDisplayTitle.make(rawTitle: title, createdAt: createdAt)
    }
}

extension RecordingProjectHistory.Entry {
    var recordedAt: Date {
        createdAt
            ?? RecordingProjectDisplayTitle.timestampDate(from: title)
            ?? RecordingProjectDisplayTitle.timestampDate(
                from: URL(fileURLWithPath: takeDirectoryPath).lastPathComponent
            )
            ?? updatedAt
    }

    var displayTitle: String {
        RecordingProjectDisplayTitle.make(rawTitle: title, createdAt: recordedAt)
    }
}

extension RecordingProjectHistory {
    mutating func sortByRecordedDate() {
        entries.sort { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt {
                return lhs.recordedAt > rhs.recordedAt
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

enum RecordingProjectDeletionDisposition {
    case trash
    case permanent
}

struct RecordingProjectDeletionRequest {
    let project: RecordingProjectHistory.Entry
    let settings: RecordingSettings
    let disposition: RecordingProjectDeletionDisposition
}

struct RecordingProjectTrashReceipt: Equatable {
    let project: RecordingProjectHistory.Entry
    let trashedDirectory: URL
}

struct RecordingProjectRestorationRequest {
    let receipt: RecordingProjectTrashReceipt
    let settings: RecordingSettings
}

struct RecordingProjectRenameRequest {
    let projectURL: URL
    let title: String
    let settings: RecordingSettings
}

struct RecordingProjectSceneRestoreRequest {
    let projectURL: URL
    let snapshot: RecordingProject
    let baseSettings: RecordingSettings
}

struct RecordingProjectEditorStateUpdateRequest {
    let projectURL: URL
    let editorState: RecordingProject.EditorStateSnapshot
    let baseSettings: RecordingSettings
}

struct RecordingProjectTimelineEditsUpdateRequest {
    let projectURL: URL
    let edits: TimelineEdits
    let baseSettings: RecordingSettings
}

struct ProjectHistoryWriteRequest {
    let history: RecordingProjectHistory
    let settings: RecordingSettings
}
