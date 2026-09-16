import Foundation

extension RecorderViewModel {
    @discardableResult
    func applyProjectSceneCorrection(_ request: EditorProjectSceneCorrectionRequest) -> Bool {
        if let layout = lastExportedProject?.edits.activeOutputLayout {
            return changeOutputScene(.init(index: request.eventIndex, mutate: { scene in
                scene = scene.corrected(request.correction, layout: layout)
            }))
        }
        guard let projectURL = lastExportedProjectURL else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        let previousProject = lastExportedProject
        do {
            lastExportedProject = try coordinator.updateProjectScene(
                at: projectURL,
                eventIndex: request.eventIndex,
                correction: request.correction
            )
            refreshRecentProjects()
            detailMessage = "Updated project segment. Export again to render the correction."
            recordEditorMutation(previousProject: previousProject, actionName: "Change Scene")
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func applyProjectSceneEdit(eventIndex: Int, _ mutate: @escaping (inout RecordingScene) -> Void) -> Bool {
        if lastExportedProject?.edits.activeOutputLayout != nil {
            return changeOutputScene(.init(index: eventIndex, mutate: mutate))
        }
        guard let projectURL = lastExportedProjectURL else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        let previousProject = lastExportedProject
        do {
            lastExportedProject = try coordinator.updateProjectScene(
                at: projectURL,
                eventIndex: eventIndex,
                mutate: mutate
            )
            recordEditorMutation(previousProject: previousProject, actionName: "Edit Scene")
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func applyProjectEditorState(_ request: EditorProjectStateUpdateRequest) -> Bool {
        guard let projectURL = lastExportedProjectURL else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        guard lastExportedProject?.editorState != request.editorState else { return true }
        let previousProject = lastExportedProject
        do {
            lastExportedProject = try coordinator.updateProjectEditorState(.init(
                projectURL: projectURL,
                editorState: request.editorState,
                baseSettings: settings
            ))
            refreshRecentProjects()
            recordEditorMutation(
                previousProject: previousProject,
                actionName: request.actionName
            )
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func applyTimelineEdits(_ request: EditorTimelineEditsChange) -> Bool {
        guard let projectURL = lastExportedProjectURL else { return false }
        var edits = request.edits
        if let project = lastExportedProject, project.edits.activeOutputLayout != nil {
            edits.textOverlays = project.edits.textOverlays
        }
        guard lastExportedProject?.edits != edits else { return true }
        let previousProject = lastExportedProject
        do {
            lastExportedProject = try TakeFileStore().updateProjectTimelineEdits(.init(
                projectURL: projectURL, edits: edits, baseSettings: settings
            ))
            refreshRecentProjects()
            recordEditorMutation(previousProject: previousProject, actionName: request.actionName)
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func splitProjectScene(at time: Double, duration: Double) -> Bool {
        if lastExportedProject?.edits.activeOutputLayout != nil {
            return splitOutputScene(.init(time: time, duration: duration))
        }
        guard let projectURL = lastExportedProjectURL else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        guard duration <= 0 || time < duration - 0.05 else {
            detailMessage = "Move the playhead before the end before splitting."
            return false
        }
        let previousProject = lastExportedProject
        do {
            lastExportedProject = try coordinator.insertProjectSceneEvent(
                at: projectURL,
                time: time
            )
            refreshRecentProjects()
            detailMessage = "Split all tracks at \(formatProjectEditTime(time))."
            recordEditorMutation(previousProject: previousProject, actionName: "Split Segment")
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
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
        guard let projectURL = lastExportedProjectURL else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        let previousProject = lastExportedProject
        do {
            lastExportedProject = try coordinator.removeProjectSceneEvent(
                at: projectURL,
                eventIndex: eventIndex
            )
            refreshRecentProjects()
            detailMessage = "Deleted scene change."
            recordEditorMutation(previousProject: previousProject, actionName: "Delete Scene Change")
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    func undoEditor() {
        guard canUndoEditor,
              let entry = editorHistory.popUndo(),
              let currentProject = lastExportedProject else { return }
        do {
            lastExportedProject = try restoreEditorProject(entry.project)
            editorHistory.pushRedo(project: currentProject, actionName: entry.actionName)
            detailMessage = "Undid \(entry.actionName.lowercased())."
            notifyEditorHistoryChanged()
        } catch {
            editorHistory.pushUndo(entry)
            detailMessage = error.localizedDescription
            notifyEditorHistoryChanged()
        }
    }

    func redoEditor() {
        guard canRedoEditor,
              let entry = editorHistory.popRedo(),
              let currentProject = lastExportedProject else { return }
        do {
            lastExportedProject = try restoreEditorProject(entry.project)
            editorHistory.pushUndo(project: currentProject, actionName: entry.actionName)
            detailMessage = "Redid \(entry.actionName.lowercased())."
            notifyEditorHistoryChanged()
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
        try coordinator.restoreProjectSceneTimeline(.init(
            projectURL: URL(fileURLWithPath: snapshot.projectPath),
            snapshot: snapshot,
            baseSettings: settings
        ))
    }

    private func recordEditorMutation(previousProject: RecordingProject?, actionName: String) {
        guard let previousProject,
              previousProject != lastExportedProject else { return }
        editorHistory.record(previous: previousProject, actionName: actionName)
        notifyEditorHistoryChanged()
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
