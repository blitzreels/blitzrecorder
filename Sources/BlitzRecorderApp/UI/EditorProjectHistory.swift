import Foundation

struct EditorProjectHistory {
    struct Entry {
        let project: RecordingProject
        let actionName: String
    }

    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private let limit = 100

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String {
        undoStack.last.map { "Undo \($0.actionName)" } ?? "Undo"
    }
    var redoTitle: String {
        redoStack.last.map { "Redo \($0.actionName)" } ?? "Redo"
    }

    mutating func record(previous: RecordingProject, actionName: String) {
        undoStack.append(Entry(project: previous, actionName: actionName))
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    mutating func popUndo() -> Entry? {
        undoStack.popLast()
    }

    mutating func pushRedo(project: RecordingProject, actionName: String) {
        redoStack.append(Entry(project: project, actionName: actionName))
    }

    mutating func popRedo() -> Entry? {
        redoStack.popLast()
    }

    mutating func pushUndo(project: RecordingProject, actionName: String) {
        undoStack.append(Entry(project: project, actionName: actionName))
    }

    mutating func pushUndo(_ entry: Entry) {
        undoStack.append(entry)
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
