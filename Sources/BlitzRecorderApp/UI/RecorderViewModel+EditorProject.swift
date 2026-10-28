import AVFoundation
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

    /// Cuts to a camera shot in a multicam project: a new part starts at the playhead showing it, or the part that
    /// starts right there changes to it. The first part changes when the playhead is at the very start.
    @discardableResult
    func cutToCameraShot(_ request: MulticamCutRequest) -> Bool {
        guard let project = lastExportedProject, project.isMulticam else { return false }
        guard project.edits.activeOutputLayout == nil else {
            detailMessage = "Camera cuts change the main layout. Switch back to it to cut between cameras."
            return false
        }
        let canvas = CaptureLayout(rawValue: project.settings.layout) ?? .horizontal
        let angles = project.cameraAngles
        let time = max(0, request.time)
        let times = project.sceneEvents.map(\.time)
        return commitEditorWrite(.init(actionName: "Cut to Camera", successMessage: nil, refreshesLibrary: false) {
            [coordinator] projectURL in
            let index: Int
            if time <= 0.05 {
                index = 0
            } else if let existing = times.firstIndex(where: { abs($0 - time) < 0.05 }) {
                index = existing
            } else {
                let inserted = try coordinator.insertProjectSceneEvent(at: projectURL, time: time)
                guard let new = inserted.sceneEvents.firstIndex(where: { abs($0.time - time) < 0.001 }) else {
                    throw RecorderError.mediaWriteFailed("The camera cut could not be placed at the playhead.")
                }
                index = new
            }
            return try coordinator.updateProjectScene(at: projectURL, eventIndex: index) { scene in
                request.shot.apply(to: &scene, .init(angles: angles, canvas: canvas, framing: request.framing))
            }
        })
    }

    /// Names a camera of a multicam project, such as after the speaker it frames. Its lanes, shots and sound
    /// picker all show the new name.
    func renameCameraAngle(_ rename: CameraAngleRenameRequest) {
        guard let project = lastExportedProject, project.cameraAngles.record(role: rename.role)?.title != rename.title,
              !rename.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = commitEditorWrite(.init(actionName: "Rename Camera", successMessage: nil, refreshesLibrary: false) {
            [coordinator] projectURL in
            try coordinator.renameProjectCameraAngle(.init(projectURL: projectURL, role: rename.role, title: rename.title))
        })
    }

    /// Plays another camera's sound in a multicam project. Its sound is extracted the first time, placed like the
    /// camera, and kept in the project folder for the next switch.
    func useProgramAudio(role: String) {
        guard let project = lastExportedProject, project.programAudioRole != role, editorSoundSwitch == nil,
              let angle = project.cameraAngles.record(role: role),
              let source = project.sources.first(where: { $0.role == role }) else { return }
        let soundURL = MulticamProjectImporter.soundURL(directory: URL(fileURLWithPath: project.takeDirectoryPath), role: role)
        editorSoundSwitch = role
        Task {
            defer { editorSoundSwitch = nil }
            do {
                if !FileManager.default.fileExists(atPath: soundURL.path) {
                    try await Self.extractSound(.init(source: source, offset: angle.offsetSeconds, destination: soundURL))
                }
                _ = commitEditorWrite(.init(actionName: "Change Sound", successMessage: "Sound now plays from \(angle.title).",
                                        refreshesLibrary: false) { [coordinator] projectURL in
                    try coordinator.updateProjectProgramAudio(.init(projectURL: projectURL, role: role, soundURL: soundURL))
                })
            } catch {
                detailMessage = error.localizedDescription
            }
        }
    }

    private struct SoundExtraction: Sendable {
        let source: RecordingProject.SourceFile
        let offset: Double
        let destination: URL
    }

    nonisolated private static func extractSound(_ request: SoundExtraction) async throws {
        let url = URL(fileURLWithPath: request.source.path)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let temporary = request.destination.deletingLastPathComponent()
            .appendingPathComponent(".\(request.destination.lastPathComponent)-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await VideoProjectImporter.extractAudio(.init(asset: AVURLAsset(url: url), destination: temporary, tracks: .first,
                                                          skippedSeconds: max(0, -request.offset), onFraction: { _ in }))
        try FileManager.default.moveItem(at: temporary, to: request.destination)
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

    /// The one path every editor change takes to disk. The change is worked out on the project this editor shows
    /// and shown at once; `ProjectSaveQueue` writes it behind, only over the revision it was made on. A save that
    /// fails or meets a newer edit from elsewhere loads the saved version instead (`finishEditorSave`).
    private func commitEditorWrite(_ edit: EditorProjectWrite) -> Bool {
        guard let projectURL = lastExportedProjectURL, let previousProject = lastExportedProject else {
            detailMessage = "No editable project is available for this recording."
            return false
        }
        do {
            let staged = try stageEditorChange(.init(projectURL: projectURL, base: previousProject) { try edit.write(projectURL) })
            lastExportedProject = staged
            if edit.refreshesLibrary { refreshLibraryEntry(for: staged) }
            if let message = edit.successMessage { detailMessage = message }
            recordEditorMutation(previousProject: previousProject, actionName: edit.actionName)
            return true
        } catch {
            detailMessage = error.localizedDescription
            return false
        }
    }

    private struct EditorChange {
        let projectURL: URL
        let base: RecordingProject
        let change: () throws -> RecordingProject
    }

    /// Runs the change on an in-memory copy of `base` and queues its save. Throws only when the change itself
    /// is invalid (for example a scene that no longer exists); disk errors arrive later in `finishEditorSave`.
    private func stageEditorChange(_ request: EditorChange) throws -> RecordingProject {
        let draft = TakeFileStore.ProjectDraft(projectURL: request.projectURL, project: request.base)
        let staged = try draft.stage(request.change)
        ProjectSaveQueue.shared.enqueue(.init(
            projectURL: request.projectURL, project: staged, baseRevision: request.base.editRevision, settings: settings,
            owner: ObjectIdentifier(self), generation: editSaveGeneration
        ) { [weak self] outcome in self?.finishEditorSave(outcome) })
        return staged
    }

    /// A queued save either landed, or could not: then this window shows what is on disk, because the changes
    /// after it were made on top of one that never saved.
    private func finishEditorSave(_ outcome: ProjectSaveQueue.Outcome) {
        switch outcome {
        case .saved, .skipped:
            return
        case let .conflict(conflict, generation):
            editSaveGeneration = generation
            guard lastExportedProject?.projectPath == conflict.current.projectPath else { return }
            loadConflictingProject(conflict)
        case let .failed(error, saved, generation):
            editSaveGeneration = generation
            detailMessage = "Your last change could not be saved: \(error.localizedDescription)"
            guard let saved, lastExportedProject?.projectPath == saved.projectPath else { return }
            lastExportedProject = saved
            clearEditorHistory()
            refreshRecentProjects()
        }
    }

    /// Another window or agent saved a newer edit of the project this editor shows. This window's own queued
    /// saves post the same notification; while any are pending, the conflict check in the queue decides instead.
    func adoptEditSavedElsewhere(_ edit: RecordingProjectEdited) {
        guard !ProjectSaveQueue.shared.hasPendingSaves(projectPath: edit.projectPath, owner: ObjectIdentifier(self)),
              let current = lastExportedProject, current.projectPath == edit.projectPath,
              edit.editRevision >= current.editRevision,
              let saved = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: edit.projectPath)) else { return }
        guard edit.editRevision > current.editRevision else {
            // Same edits with a new title or export: refresh them and keep undo history.
            if saved.editRevision == current.editRevision, saved.updatedAt > current.updatedAt { lastExportedProject = saved }
            return
        }
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
        let projectURL = URL(fileURLWithPath: snapshot.projectPath)
        return try stageEditorChange(.init(projectURL: projectURL, base: lastExportedProject ?? snapshot) { [coordinator, settings] in
            try coordinator.restoreProjectSceneTimeline(.init(
                projectURL: projectURL,
                snapshot: snapshot,
                baseSettings: settings
            ))
        })
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

struct CameraAngleRenameRequest {
    let role: String
    let title: String
}

struct MulticamCutRequest {
    let shot: MulticamShot
    let framing: MulticamShot.Framing
    /// Seconds on the take timeline where the shot starts.
    let time: Double
}
