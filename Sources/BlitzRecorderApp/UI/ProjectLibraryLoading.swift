import AVFoundation
import SwiftUI

struct ProjectLibraryWorkPolicy: Equatable {
    let section: ProjectLibraryNavigationState.Section
    let isExporting: Bool

    var loadsLocalProjects: Bool { section == .recordings }
    var generatesThumbnails: Bool { loadsLocalProjects && !isExporting }
    var preparesPlayback: Bool { loadsLocalProjects }
    var analyzesAudio: Bool { loadsLocalProjects && !isExporting }
}

extension ProjectLibraryView {
    var workPolicy: ProjectLibraryWorkPolicy {
        .init(section: vm.projectLibraryNavigation.section, isExporting: vm.isExporting)
    }

    struct MetadataTaskID: Equatable {
        let section: ProjectLibraryNavigationState.Section
        let isExporting: Bool
        let projects: [RecordingProjectHistory.Entry]
    }

    var metadataTaskID: MetadataTaskID {
        .init(section: vm.projectLibraryNavigation.section, isExporting: vm.isExporting, projects: vm.recentProjects)
    }

    func loadMetadata() async {
        let policy = workPolicy
        guard policy.loadsLocalProjects else { return }
        metadataStore.retain(vm.recentProjects)
        let pending = vm.recentProjects.filter {
            metadataStore.needsLoad(.init(entry: $0, generatesThumbnails: policy.generatesThumbnails))
        }
        guard !pending.isEmpty else { return }
        let selectedIDs = vm.projectLibraryNavigation.selectedProjectIDs.isEmpty
            ? Set(filteredProjects.prefix(1).map(\.id))
            : vm.projectLibraryNavigation.selectedProjectIDs
        let selected = pending.filter { selectedIDs.contains($0.id) }
        let remaining = pending.filter { !selectedIDs.contains($0.id) }
        let ordered = selected + remaining
        let concurrency = policy.isExporting ? 1 : 2
        let batches = stride(from: 0, to: ordered.count, by: concurrency).map {
            Array(ordered[$0..<min($0 + concurrency, ordered.count)])
        }
        var pendingUpdates: [(RecordingProjectHistory.Entry, ProjectLibraryMetadata)] = []
        var lastUpdate: TimeInterval = 0
        for (index, batch) in batches.enumerated() {
            guard !Task.isCancelled else { return }
            let loaded = await withTaskGroup(
                of: (RecordingProjectHistory.Entry, ProjectLibraryMetadata).self
            ) { group in
                for project in batch {
                    group.addTask(priority: .utility) {
                        (project, await ProjectLibraryMetadataLoader.load(.init(
                            entry: project, generatesThumbnails: policy.generatesThumbnails)))
                    }
                }
                var results: [(RecordingProjectHistory.Entry, ProjectLibraryMetadata)] = []
                for await result in group { results.append(result) }
                return results
            }
            guard !Task.isCancelled else { return }
            pendingUpdates.append(contentsOf: loaded)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastUpdate >= 0.15 || index == batches.count - 1 {
                metadataStore.store(.init(values: pendingUpdates, generatesThumbnails: policy.generatesThumbnails))
                pendingUpdates.removeAll(keepingCapacity: true)
                lastUpdate = now
            }
        }
    }

    func loadSelectedTranscript() async {
        guard workPolicy.loadsLocalProjects, let project = selectedProject else { return }
        let path = project.projectPath
        let loaded = await Task.detached(priority: .utility) { () -> RecordingTranscript? in
            guard let recordingProject = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: path)) else {
                return nil
            }
            let artifactStore = TranscriptArtifactStore()
            guard let transcript = try? artifactStore.load(from: artifactStore.locations(for: recordingProject).jsonURL) else {
                return nil
            }
            return transcript.mappedToEditedTimeline(TimelineTimeMap(
                takeDuration: MediaTime(seconds: max(transcript.duration, 0)), cuts: recordingProject.edits.enabledCuts))
        }.value
        guard !Task.isCancelled else { return }
        if let loaded {
            transcriptByProjectID[project.id] = loaded
            transcriptUnavailableIDs.remove(project.id)
        } else {
            transcriptByProjectID.removeValue(forKey: project.id)
            transcriptUnavailableIDs.insert(project.id)
        }
    }

    func loadSelectedPlayback() async {
        guard workPolicy.preparesPlayback, let project = selectedProject else {
            projectPlayback.teardown()
            playbackProjectID = nil
            playbackProjectPath = nil
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
            try await Task.sleep(for: .milliseconds(150))
            let projectPath = project.projectPath
            let loaded = try await Task.detached(priority: .utility) {
                let project = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: projectPath))
                return (project, ProjectLibraryPreviewMedia.editedVideoURL(for: project))
            }.value
            guard !Task.isCancelled else { return }
            let (recordingProject, editedURL) = loaded
            if let editedURL {
                await projectPlayback.loadExported(url: editedURL, title: recordingProject.title)
            } else {
                await projectPlayback.load(project: recordingProject, baseSettings: vm.settings)
            }
            guard !Task.isCancelled,
                  selectedProject?.id == project.id,
                  projectPlayback.isReady else { return }
            playbackProjectID = project.id
            playbackProjectPath = project.projectPath
        } catch {
            guard !Task.isCancelled else { return }
            playbackLoadError = error.localizedDescription
        }
    }

    func loadSelectedWaveform() async {
        guard workPolicy.analyzesAudio, let project = selectedProject,
              playbackProjectID == project.id, projectPlayback.isReady else { return }
        let path = project.projectPath
        let url = await Task.detached(priority: .utility) { () -> URL? in
            guard let project = try? TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: path)) else {
                return nil
            }
            return ProjectLibraryPreviewMedia.editedVideoURL(for: project) ?? project.sources
                .first { $0.role == "microphone" && $0.exists }.map { URL(fileURLWithPath: $0.path) }
        }.value
        guard !Task.isCancelled,
              projectPlayback.filePlayer != nil || abs(projectPlayback.outputDuration - projectPlayback.duration) <= 0.25
        else { return }
        let samples = await ProjectLibraryWaveform.overview(of: url)
        guard !Task.isCancelled, selectedProject?.id == project.id else { return }
        playbackWaveformSamples = samples
    }

    func loadSelectedMediaAssets() async {
        guard workPolicy.loadsLocalProjects, let projectEntry = selectedProject else {
            mediaAssets = []
            mediaAssetsProjectID = nil
            isLoadingMediaAssets = false
            return
        }

        let projectID = projectEntry.id
        isLoadingMediaAssets = true
        do {
            let projectPath = projectEntry.projectPath
            let loadedAssets = try await Task.detached(priority: .utility) {
                let recordingProject = try TakeFileStore().loadRecordingProject(at: URL(fileURLWithPath: projectPath))
                var assets = EditorAsset.assets(project: recordingProject, finalVideoURL: nil).filter(\.isPlayable)
                var knownPaths = Set(assets.map { $0.url.standardizedFileURL.path })
                for export in recordingProject.exports.reversed() {
                    let url = URL(fileURLWithPath: export.path)
                    guard knownPaths.insert(url.standardizedFileURL.path).inserted else { continue }
                    assets.append(EditorAsset.output(url: url))
                }
                return assets
            }.value
            guard !Task.isCancelled,
                  selectedProject?.id == projectID else {
                return
            }
            mediaAssets = loadedAssets
            mediaAssetsProjectID = projectID
            await projectWaveformLibrary.loadAssets(.init(
                assets: loadedAssets, purpose: workPolicy.isExporting ? .metadata : .library))
            guard !Task.isCancelled,
                  selectedProject?.id == projectID else {
                return
            }
            isLoadingMediaAssets = false
        } catch {
            guard !Task.isCancelled, selectedProject?.id == projectID else { return }
            mediaAssets = []
            mediaAssetsProjectID = projectID
            isLoadingMediaAssets = false
        }
    }

    var transcriptSearchTaskID: String {
        guard workPolicy.loadsLocalProjects, !vm.projectLibraryNavigation.searchText.isEmpty else { return "inactive" }
        return vm.projectLibraryNavigation.searchText + vm.recentProjects.map {
            "\($0.id)-\($0.updatedAt)-\(vm.transcriptionController.status(for: $0).label)"
        }.joined()
    }

    func searchTranscripts() async {
        let query = vm.projectLibraryNavigation.searchText
        transcriptMatches = [:]
        guard workPolicy.loadsLocalProjects, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        guard workPolicy.loadsLocalProjects, let project = selectedProject else { return "none" }
        let status = vm.transcriptionController.status(for: project)
        return "\(project.id.uuidString)-\(status.label)"
    }

    var playbackTaskID: String {
        guard workPolicy.preparesPlayback else { return "inactive" }
        return selectedProject?.projectPath ?? "none"
    }

    var mediaTaskID: String {
        guard workPolicy.loadsLocalProjects else { return "inactive" }
        return "\(selectedProject?.projectPath ?? "none")-\(workPolicy.isExporting)"
    }

    var waveformTaskID: String {
        guard workPolicy.analyzesAudio else { return "inactive" }
        return playbackProjectID?.uuidString ?? "none"
    }

}

enum ProjectLibraryWaveform {
    static func overview(of url: URL?) async -> [Float] {
        guard let url else { return [] }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else { return [] }
        return await EditorAudioWaveform.load(.init(asset: asset, duration: duration.seconds))?.overview ?? []
    }
}
