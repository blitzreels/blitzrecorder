import Foundation

extension RecorderViewModel {
    @discardableResult
    func applyProjectSceneCorrection(_ request: EditorProjectSceneCorrectionRequest) -> Bool {
        if let layout = lastExportedProject?.edits.activeOutputLayout {
            return changeOutputScene(.init(index: request.eventIndex, mutate: { scene in
                scene = scene.corrected(request.correction, layout: layout)
            }))
        }
        return commitEditorWrite(.init(
            actionName: "Change Scene",
            successMessage: "Updated project segment. Export again to render the correction.",
            refreshesLibrary: true
        ) { [coordinator] projectURL in
            try coordinator.updateProjectScene(at: projectURL, eventIndex: request.eventIndex, correction: request.correction)
        })
    }

    @discardableResult
    func applyProjectSceneEdit(eventIndex: Int, _ mutate: @escaping (inout RecordingScene) -> Void) -> Bool {
        if lastExportedProject?.edits.activeOutputLayout != nil {
            return changeOutputScene(.init(index: eventIndex, mutate: mutate))
        }
        return commitEditorWrite(.init(actionName: "Edit Scene", successMessage: nil, refreshesLibrary: false) {
            [coordinator] projectURL in
            try coordinator.updateProjectScene(at: projectURL, eventIndex: eventIndex, mutate: mutate)
        })
    }

    @discardableResult
    func applyProjectEditorState(_ request: EditorProjectStateUpdateRequest) -> Bool {
        guard lastExportedProject?.editorState != request.editorState else { return true }
        return commitEditorWrite(.init(actionName: request.actionName, successMessage: nil, refreshesLibrary: true) {
            [coordinator, settings] projectURL in
            try coordinator.updateProjectEditorState(.init(
                projectURL: projectURL,
                editorState: request.editorState,
                baseSettings: settings
            ))
        })
    }

    @discardableResult
    func applyTimelineEdits(_ request: EditorTimelineEditsChange) -> Bool {
        guard lastExportedProjectURL != nil else { return false }
        var edits = request.edits
        if let project = lastExportedProject, project.edits.activeOutputLayout != nil {
            edits.textOverlays = project.edits.textOverlays
        }
        guard lastExportedProject?.edits != edits else { return true }
        return commitEditorWrite(.init(actionName: request.actionName, successMessage: nil, refreshesLibrary: true) {
            [coordinator, settings] projectURL in
            try coordinator.updateProjectTimelineEdits(.init(projectURL: projectURL, edits: edits, baseSettings: settings))
        })
    }

    @discardableResult
    func splitProjectScene(at time: Double, duration: Double) -> Bool {
        if lastExportedProject?.edits.activeOutputLayout != nil {
            return splitOutputScene(.init(time: time, duration: duration))
        }
        guard duration <= 0 || time < duration - 0.05 else {
            detailMessage = "Move the playhead before the end before splitting."
            return false
        }
        return commitEditorWrite(.init(
            actionName: "Split Segment",
            successMessage: "Split all tracks at \(formatProjectEditTime(time)).",
            refreshesLibrary: true
        ) { [coordinator] projectURL in
            try coordinator.insertProjectSceneEvent(at: projectURL, time: time)
        })
    }

    @discardableResult
    func deleteProjectSegment(_ request: EditorProjectSegmentDeletion) -> Bool {
        guard let project = editorProject,
            let range = EditorTimeRange.segment(.init(
                eventTimes: TakeFileStore().sceneEvents(from: project).map(\.time),
                index: request.index, duration: request.duration
            )),
            let edits = EditorTimeRange.removing(.init(
                range: range, edits: lastExportedProject?.edits ?? project.edits, takeDuration: request.duration
            ))
        else {
            detailMessage = "Select a segment to delete and leave at least 0.1 seconds in the recording."
            return false
        }
        return applyTimelineEdits(.init(edits: edits, actionName: "Delete Segment"))
    }

    @discardableResult
    func removeProjectSceneEvent(eventIndex: Int) -> Bool {
        if lastExportedProject?.edits.activeOutputLayout != nil { return joinOutputScene(eventIndex) }
        return commitEditorWrite(.init(
            actionName: "Delete Scene Change",
            successMessage: "Deleted scene change.",
            refreshesLibrary: true
        ) { [coordinator] projectURL in
            try coordinator.removeProjectSceneEvent(at: projectURL, eventIndex: eventIndex)
        })
    }

    private struct EditorProjectWrite {
        let actionName: String
        let successMessage: String?
        let refreshesLibrary: Bool
        let write: (URL) throws -> RecordingProject
    }

    /// The one path every editor change takes to disk: it saves only over the revision this editor loaded,
    /// records the undo step, and on a conflict loads the saved version instead of overwriting it.
    private func commitEditorWrite(_ edit: EditorProjectWrite) -> Bool {
        guard let projectURL = lastExportedProjectURL, let previousProject = lastExportedProject else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        isSavingProjectEdit = true
        defer { isSavingProjectEdit = false }
        do {
            lastExportedProject = try TakeFileStore().editProject(.init(
                projectURL: projectURL, expectedEditRevision: previousProject.editRevision
            )) { try edit.write(projectURL) }
            if edit.refreshesLibrary { refreshRecentProjects() }
            if let message = edit.successMessage { detailMessage = message }
            recordEditorMutation(previousProject: previousProject, actionName: edit.actionName)
            return true
        } catch let conflict as ProjectEditConflict {
            loadConflictingProject(conflict)
            return false
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    /// Another window or agent saved a newer edit of the project this editor shows. The notification can
    /// arrive while this editor is saving its own edit, which `isSavingProjectEdit` filters out.
    func adoptEditSavedElsewhere(_ edit: RecordingProjectEdited) {
        guard !isSavingProjectEdit, let current = lastExportedProject, current.projectPath == edit.projectPath,
              edit.editRevision > current.editRevision,
              let saved = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: edit.projectPath)) else { return }
        lastExportedProject = saved
        clearEditorHistory()
        detailMessage = "Loaded changes saved in another window."
    }

    /// Undo steps were taken from the stale copy; replaying them would undo someone else's change.
    private func loadConflictingProject(_ conflict: ProjectEditConflict) {
        lastExportedProject = conflict.current
        clearEditorHistory()
        refreshRecentProjects()
        detailMessage = conflict.localizedDescription
    }

    func undoEditor() {
        if studioMode == .projects {
            guard canUndoEditor else { return }
            transcriptUndoManager.undo()
            notifyEditorHistoryChanged()
            return
        }
        guard canUndoEditor,
              let entry = editorHistory.popUndo(),
              let currentProject = lastExportedProject else { return }
        do {
            lastExportedProject = try restoreEditorProject(entry.project)
            editorHistory.pushRedo(project: currentProject, actionName: entry.actionName)
            detailMessage = "Undid \(entry.actionName.lowercased())."
            notifyEditorHistoryChanged()
        } catch let conflict as ProjectEditConflict {
            loadConflictingProject(conflict)
        } catch {
            editorHistory.pushUndo(entry)
            detailMessage = error.localizedDescription
            notifyEditorHistoryChanged()
        }
    }

    func redoEditor() {
        if studioMode == .projects {
            guard canRedoEditor else { return }
            transcriptUndoManager.redo()
            notifyEditorHistoryChanged()
            return
        }
        guard canRedoEditor,
              let entry = editorHistory.popRedo(),
              let currentProject = lastExportedProject else { return }
        do {
            lastExportedProject = try restoreEditorProject(entry.project)
            editorHistory.pushUndo(project: currentProject, actionName: entry.actionName)
            detailMessage = "Redid \(entry.actionName.lowercased())."
            notifyEditorHistoryChanged()
        } catch let conflict as ProjectEditConflict {
            loadConflictingProject(conflict)
        } catch {
            editorHistory.pushRedo(project: entry.project, actionName: entry.actionName)
            detailMessage = error.localizedDescription
            notifyEditorHistoryChanged()
        }
    }

    func clearEditorHistory() {
        guard editorHistory.canUndo || editorHistory.canRedo else { return }
        editorHistory.clear()
        notifyEditorHistoryChanged()
    }

    private func restoreEditorProject(_ snapshot: RecordingProject) throws -> RecordingProject {
        isSavingProjectEdit = true
        defer { isSavingProjectEdit = false }
        let projectURL = URL(fileURLWithPath: snapshot.projectPath)
        return try TakeFileStore().editProject(.init(
            projectURL: projectURL, expectedEditRevision: lastExportedProject?.editRevision ?? snapshot.editRevision
        )) {
            try coordinator.restoreProjectSceneTimeline(.init(
                projectURL: projectURL,
                snapshot: snapshot,
                baseSettings: settings
            ))
        }
    }

    private func recordEditorMutation(previousProject: RecordingProject?, actionName: String) {
        guard let previousProject,
              previousProject != lastExportedProject else { return }
        editorHistory.record(previous: previousProject, actionName: actionName)
        notifyEditorHistoryChanged()
    }

    func moveEditorHistory(to destination: RecorderViewModel) {
        destination.editorHistory = editorHistory
        destination.notifyEditorHistoryChanged()
        clearEditorHistory()
    }

    private func notifyEditorHistoryChanged() {
        editorHistoryRevision &+= 1
        onEditorHistoryChanged?()
    }

    private func formatProjectEditTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
