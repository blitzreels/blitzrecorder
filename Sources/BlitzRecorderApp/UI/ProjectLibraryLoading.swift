import SwiftUI

extension ProjectLibraryView {
    func loadMetadata() async {
        metadataStore.retain(vm.recentProjects)
        let pending = vm.recentProjects.filter(metadataStore.needsLoad)
        guard !pending.isEmpty else { return }
        let selectedIDs = vm.projectLibraryNavigation.selectedProjectIDs.isEmpty
            ? Set(filteredProjects.prefix(1).map(\.id))
            : vm.projectLibraryNavigation.selectedProjectIDs
        let selected = pending.filter { selectedIDs.contains($0.id) }
        let remaining = pending.filter { !selectedIDs.contains($0.id) }
        let batches = (selected.isEmpty ? [] : [selected]) + stride(from: 0, to: remaining.count, by: 6).map {
            Array(remaining[$0..<min($0 + 6, remaining.count)])
        }
        for batch in batches {
            guard !Task.isCancelled else { return }
            let loaded = await withTaskGroup(
                of: (RecordingProjectHistory.Entry, ProjectLibraryMetadata).self
            ) { group in
                for project in batch {
                    group.addTask { (project, await ProjectLibraryMetadataLoader.load(project)) }
                }
                var results: [(RecordingProjectHistory.Entry, ProjectLibraryMetadata)] = []
                for await result in group { results.append(result) }
                return results
            }
            guard !Task.isCancelled else { return }
            metadataStore.store(loaded)
        }
    }

    func loadSelectedTranscript() async {
        guard let project = selectedProject else { return }
        let path = project.projectPath
        let loaded = await Task.detached(priority: .userInitiated) { () -> (RecordingProject, RecordingTranscript)? in
            guard let recordingProject = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: path)) else {
                return nil
            }
            let artifactStore = TranscriptArtifactStore()
            guard let transcript = try? artifactStore.load(from: artifactStore.locations(for: recordingProject).jsonURL) else {
                return nil
            }
            return (recordingProject, transcript)
        }.value
        guard !Task.isCancelled else { return }
        if let (recordingProject, transcript) = loaded {
            transcriptByProjectID[project.id] = editedTranscript(transcript, project: recordingProject)
            transcriptUnavailableIDs.remove(project.id)
        } else {
            transcriptByProjectID.removeValue(forKey: project.id)
            transcriptUnavailableIDs.insert(project.id)
        }
    }

    func loadSelectedPlayback() async {
        guard let project = selectedProject else {
            return
        }
        guard ProjectLibraryPlaybackReloadPolicy.shouldReload(.init(
            selectedProjectPath: project.projectPath,
            loadedProjectPath: playbackProjectPath,
            hasActivePlayback: projectPlayback.isReady
        )) else { return }

        playbackProjectID = nil
        playbackProjectPath = nil
        playbackWaveformSamples = []
        projectPlayback.teardown()
        playbackLoadError = nil

        do {
            let recordingProject = try TakeFileStore().loadRecordingProject(
                at: URL(fileURLWithPath: project.projectPath)
            )
            guard !Task.isCancelled else { return }
            let editedURL = ProjectLibraryPreviewMedia.editedVideoURL(for: recordingProject)
            if let editedURL {
                await projectPlayback.loadExported(url: editedURL, title: recordingProject.title)
            } else {
                await projectPlayback.load(
                    project: recordingProject,
                    baseSettings: vm.settings
                )
            }
            guard !Task.isCancelled,
                  selectedProject?.id == project.id,
                  projectPlayback.isReady else {
                return
            }
            playbackProjectID = project.id
            playbackProjectPath = project.projectPath

            guard let editedURL, projectPlayback.isExportedPlayback else { return }
            let waveformAsset = EditorAsset.output(url: editedURL)
            await projectWaveformLibrary.loadAssets([waveformAsset])
            guard !Task.isCancelled,
                  selectedProject?.id == project.id else {
                return
            }
            playbackWaveformSamples = projectWaveformLibrary.waveforms[waveformAsset.id] ?? []
        } catch {
            guard !Task.isCancelled else { return }
            playbackLoadError = error.localizedDescription
        }
    }

    func loadSelectedMediaAssets() async {
        guard let projectEntry = selectedProject else {
            mediaAssets = []
            mediaAssetsProjectID = nil
            isLoadingMediaAssets = false
            return
        }

        let projectID = projectEntry.id
        isLoadingMediaAssets = true
        do {
            let recordingProject = try TakeFileStore().loadRecordingProject(
                at: URL(fileURLWithPath: projectEntry.projectPath)
            )
            var loadedAssets = EditorAsset.assets(
                project: recordingProject,
                finalVideoURL: nil
            ).filter(\.isPlayable)
            var knownPaths = Set(loadedAssets.map { $0.url.standardizedFileURL.path })
            for export in recordingProject.exports.reversed() {
                let url = URL(fileURLWithPath: export.path)
                let path = url.standardizedFileURL.path
                guard !knownPaths.contains(path) else { continue }
                loadedAssets.append(EditorAsset.output(url: url))
                knownPaths.insert(path)
            }
            guard !Task.isCancelled,
                  selectedProject?.id == projectID else {
                return
            }
            mediaAssets = loadedAssets
            mediaAssetsProjectID = projectID
            await projectWaveformLibrary.loadAssets(loadedAssets)
            guard !Task.isCancelled,
                  selectedProject?.id == projectID else {
                return
            }
            isLoadingMediaAssets = false
        } catch {
            guard selectedProject?.id == projectID else { return }
            mediaAssets = []
            mediaAssetsProjectID = projectID
            isLoadingMediaAssets = false
        }
    }

    private func editedTranscript(
        _ transcript: RecordingTranscript?,
        project: RecordingProject
    ) -> RecordingTranscript? {
        guard let transcript else { return nil }
        return transcript.mappedToEditedTimeline(
            TimelineTimeMap(
                takeDuration: MediaTime(seconds: max(transcript.duration, 0)),
                cuts: project.edits.enabledCuts
            )
        )
    }

    var transcriptSearchTaskID: String {
        vm.projectLibraryNavigation.searchText + vm.recentProjects.map {
            "\($0.id)-\($0.updatedAt)-\(vm.transcriptionController.status(for: $0).label)"
        }.joined()
    }

    func searchTranscripts() async {
        let query = vm.projectLibraryNavigation.searchText
        transcriptMatches = [:]
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearchingTranscripts = false
            return
        }
        isSearchingTranscripts = true
        do {
            try await Task.sleep(for: .milliseconds(180))
            let matches = try await transcriptSearch.search(.init(query: query, projects: vm.recentProjects))
            try Task.checkCancellation()
            transcriptMatches = matches
            isSearchingTranscripts = false
        } catch {
            if !Task.isCancelled { isSearchingTranscripts = false }
        }
    }

    var transcriptTaskID: String {
        guard let project = selectedProject else { return "none" }
        let status = vm.transcriptionController.status(for: project)
        return "\(project.id.uuidString)-\(status.label)"
    }

    var playbackTaskID: String {
        selectedProject?.projectPath ?? "none"
    }

    var mediaTaskID: String {
        selectedProject?.projectPath ?? "inactive"
    }

}
