import os
import AppKit
import AVFoundation
import BlitzRecorderCore
import Foundation
import ScreenCaptureKit

@MainActor
extension RecorderCaptureRuntime {
    func mergeLastTake() {
        guard let lastTake else {
            onMessage?("No take to merge yet.")
            return
        }

        onExportFailure?(nil)
        Task {
            do {
                let outputAccess = try takeFileStore.prepareOutputDirectory(settings: settings)
                defer { outputAccess.stop() }
                let url = try await Merger.exportFinalVideo(take: lastTake, settings: settings)
                let sourceDirectory = lastTake.scratchDirectory
                self.recordingSession.clearLastTake()
                let savedOutput = SavedRecordingOutput(url: url, sourceDirectory: sourceDirectory, warning: nil)
                onSavedRecording?(savedOutput)
                onMessage?(savedOutput.userMessage)
            } catch {
                exportLog.error("Final video export failed: \(error.recorderFailureDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
                onMessage?("Final video export failed: \(error.recorderFailureDescription)")
                onExportFailure?("Final video export failed. \(error.recorderFailureDescription)")
            }
        }
    }

    func exportProject(_ request: ProjectExportRequest) {
        Task {
            try? await exportProjectForAgent(request)
        }
    }

    func exportProjectForAgent(_ request: ProjectExportRequest) async throws -> SavedRecordingOutput {
        guard recordingSession.beginExport() else {
            let message = RecordingExportCopy.waitForRecording
            onMessage?(message)
            throw RecorderError.mediaWriteFailed(message)
        }

        onRenderProgress?(0)
        onExportFailure?(nil)
        onMessage?(RecordingExportCopy.exporting(request.outputFormat))

        defer {
            recordingSession.finishExport()
            refreshAudioLevelMonitoring()
        }

        do {
            let savedOutput = try await performProjectExport(request)
            onRenderProgress?(1)
            onSavedRecording?(savedOutput)
            onMessage?(savedOutput.userMessage)
            return savedOutput
        } catch {
            exportLog.error("Project export failed (destination \(request.destinationURL.path, privacy: .public)): \(error.recorderFailureDescription, privacy: .public) | \(String(describing: error), privacy: .public)")
            onMessage?(RecordingExportCopy.failed(error))
            onExportFailure?(error.recorderFailureDescription)
            throw error
        }
    }

    func performProjectExport(_ request: ProjectExportRequest) async throws -> SavedRecordingOutput {
        var access = SecurityScopedResourceAccess(
            urls: [request.destinationURL, request.backgroundMusic?.url].compactMap { $0 }
        )
        access.start()
        defer { access.stop() }

        let project = try takeFileStore.loadRecordingProject(at: request.projectURL)
        let captureOutputFormat = ProjectExportRenderPlan.captureOutputFormat(
            project: project,
            fallback: settings.outputVideoFormat
        )
        let captureSettings = takeFileStore.recordingSettings(
            from: project,
            baseSettings: settings,
            outputFormat: captureOutputFormat
        )
        let exportSettings = takeFileStore.recordingSettings(
            from: project,
            baseSettings: settings,
            outputFormat: request.outputFormat
        )
        let outputAccess = try takeFileStore.prepareOutputDirectory(settings: exportSettings)
        defer { outputAccess.stop() }

        let take = takeFileStore.recordingTake(
            from: project,
            settings: exportSettings,
            outputFormat: request.outputFormat
        )
        let outputProject = project.outputProject(for: request.outputLayout ?? project.selectedOutputLayout)
        let context = ProjectExportRenderPlan.context(
            request: request,
            captureSettings: captureSettings,
            exportSettings: exportSettings,
            take: take,
            originalSceneEvents: takeFileStore.sceneEvents(from: project),
            outputProject: outputProject,
            outputSceneEvents: takeFileStore.sceneEvents(from: outputProject)
        )

        let url = try await Merger.exportFinalVideo(FinalVideoExportRequest(
            take: context.take,
            settings: context.renderSettings,
            sceneEvents: context.renderSceneEvents,
            backgroundMusic: request.backgroundMusic,
            destinationURL: request.destinationURL,
            progressHandler: { [weak self] progress in
                self?.onRenderProgress?(progress)
            },
            timelineEdits: outputProject.edits,
            playbackRate: request.playbackRate
        ))

        try takeFileStore.writeSourceTakeManifest(
            for: context.take,
            settings: context.captureSettings,
            finalVideoURL: url
        )
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let exportRecord = ProjectExportRenderPlan.exportRecord(
            url: url,
            request: request,
            renderSettings: context.renderSettings,
            fileSizeBytes: resourceValues?.fileSize.map(Int64.init)
        )
        try takeFileStore.writeRecordingProject(
            for: context.take,
            settings: context.captureSettings,
            sceneEvents: context.originalSceneEvents,
            finalVideoURL: url,
            chapters: project.chapters,
            editorTimeline: project.editorTimeline,
            editorState: project.editorState,
            exportRecord: exportRecord
        )
        await HostingExportMetadata.save(.init(fileURL: url, project: outputProject, playbackRate: request.playbackRate))
        return ProjectExportRenderPlan.savedOutput(url: url, take: context.take)
    }

    func mutatingIdleProject<T>(_ body: () throws -> T) throws -> T {
        guard state == .idle else {
            throw RecorderError.mediaWriteFailed(
                "Wait for the current recording task to finish before editing the project."
            )
        }
        return try body()
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        correction: RecordingProjectSceneCorrection
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            let project = try takeFileStore.updateProjectSceneEvent(
                at: projectURL,
                eventIndex: eventIndex,
                correction: correction,
                baseSettings: settings
            )
            onMessage?("Updated project source segment.")
            return project
        }
    }

    func updateProjectScene(
        at projectURL: URL,
        eventIndex: Int,
        mutate: (inout RecordingScene) -> Void
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.updateProjectScene(
                at: projectURL,
                eventIndex: eventIndex,
                baseSettings: settings,
                mutate: mutate
            )
        }
    }

    func insertProjectSceneEvent(at projectURL: URL, time: Double) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.insertProjectSceneEvent(
                at: projectURL,
                time: time,
                baseSettings: settings
            )
        }
    }

    func removeProjectSceneEvent(at projectURL: URL, eventIndex: Int) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.removeProjectSceneEvent(
                at: projectURL,
                eventIndex: eventIndex,
                baseSettings: settings
            )
        }
    }

    func restoreProjectSceneTimeline(
        _ request: RecordingProjectSceneRestoreRequest
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.restoreProjectSceneTimeline(request)
        }
    }

    func updateProjectEditorState(
        _ request: RecordingProjectEditorStateUpdateRequest
    ) throws -> RecordingProject {
        try mutatingIdleProject {
            try takeFileStore.updateProjectEditorState(request)
        }
    }

    func zoomIn() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.zoomIn()
    }

    func zoomOut() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.zoomOut()
    }

    func resetZoom() {
        guard !takeRecording.isUsingLiveCompositor else { return }
        screenRecorder.resetZoom()
    }

    func openOutputFolder() {
        NSWorkspace.shared.open(settings.outputDirectory)
    }

    var shouldUseLiveCompositor: Bool {
        TakeRecordingRuntime.shouldUseLiveCompositor(
            settings: settings,
            isRemoteCameraSelected: isRemoteCameraSelected
        )
    }

    func localCaptureSettings(usesRemoteCamera: Bool) -> RecordingSettings {
        takeRecording.localCaptureSettings(settings, usesRemoteCamera: usesRemoteCamera)
    }

    func currentLocalCaptureSettings() -> RecordingSettings {
        localCaptureSettings(
            usesRemoteCamera: settings.enabledSources.contains(.camera) && isRemoteCameraSelected
        )
    }
}
