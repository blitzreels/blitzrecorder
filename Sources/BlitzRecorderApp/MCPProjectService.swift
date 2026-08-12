import Foundation

struct MCPProjectsResponse: Codable, Equatable {
    let projects: [MCPProjectSummary]
    let totalMatched: Int
    let returned: Int
    let offset: Int
}

struct MCPProjectListRequest {
    let query: String?
    let recordedAfter: Date?
    let recordedBefore: Date?
    let hasTranscript: Bool?
    let limit: Int
    let offset: Int

    static let all = MCPProjectListRequest(
        query: nil,
        recordedAfter: nil,
        recordedBefore: nil,
        hasTranscript: nil,
        limit: 100,
        offset: 0
    )
}

struct MCPProjectSummary: Codable, Equatable {
    let id: UUID
    let title: String
    let recordedAt: Date
    let updatedAt: Date
    let sourceResolution: String?
    let sourceFramesPerSecond: Int?
    let captureSourceRoles: [String]
    let missingCaptureSourceRoles: [String]
    let canExport: Bool
    let hasTranscript: Bool
    let exportCount: Int
}

struct MCPProjectDetailsResponse: Codable, Equatable {
    struct Source: Codable, Equatable {
        let role: String
        let path: String
        let exists: Bool
    }

    struct ExportRecipe: Codable, Equatable {
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
    }

    struct Export: Codable, Equatable {
        let id: UUID
        let createdAt: Date
        let path: String
        let exists: Bool
        let format: String
        let resolution: String
        let framesPerSecond: Int
        let quality: String
        let fileSizeBytes: Int64?
    }

    let id: UUID
    let title: String
    let recordedAt: Date
    let updatedAt: Date
    let sourceResolution: String
    let sourceFramesPerSecond: Int
    let sources: [Source]
    let missingCaptureSourceRoles: [String]
    let canExport: Bool
    let hasTranscript: Bool
    let exportRecipe: ExportRecipe
    let exports: [Export]
}

struct MCPTranscriptRequest {
    let projectID: UUID
}

struct MCPTranscriptResponse: Codable, Equatable {
    let projectID: UUID
    let title: String
    let duration: TimeInterval
    let wordCount: Int
    let speakerCount: Int
    let transcript: String
}

struct MCPExportStartRequest {
    let projectIDs: [UUID]
    let outputDirectory: URL?
}

struct MCPExportJobResponse: Codable, Equatable {
    struct CompletedExport: Codable, Equatable {
        let projectID: UUID
        let title: String
        let path: String
    }

    struct FailedExport: Codable, Equatable {
        let projectID: UUID
        let title: String
        let error: String
    }

    let jobID: UUID
    let status: String
    let outputDirectory: String
    let projectCount: Int
    let currentProjectID: UUID?
    let pendingProjectIDs: [UUID]
    let completed: [CompletedExport]
    let failed: [FailedExport]
}

enum MCPProjectServiceError: LocalizedError {
    case emptyProjectSelection
    case projectNotFound(UUID)
    case transcriptNotFound(UUID)
    case exportAlreadyRunning
    case exportJobNotFound(UUID)
    case unavailable4KExport(UUID)
    case outputDirectoryNotAuthorized(requested: String, configured: String)

    var errorDescription: String? {
        switch self {
        case .emptyProjectSelection:
            return "Select at least one project to export."
        case .projectNotFound(let id):
            return "Project not found: \(id.uuidString)."
        case .transcriptNotFound(let id):
            return "Transcript not found for project: \(id.uuidString)."
        case .exportAlreadyRunning:
            return "A BlitzRecorder MCP export job is already running."
        case .exportJobNotFound(let id):
            return "Export job not found: \(id.uuidString)."
        case .unavailable4KExport(let id):
            return "Project \(id.uuidString) requires 4K export access."
        case .outputDirectoryNotAuthorized(let requested, let configured):
            return "Output directory \(requested) is not authorized. Choose \(configured) or one of its subfolders."
        }
    }
}

@MainActor
final class MCPProjectService {
    private struct SelectedProject {
        let entry: RecordingProjectHistory.Entry
        let project: RecordingProject
    }

    private struct RunJobRequest {
        let jobID: UUID
        let projects: [SelectedProject]
        let outputDirectory: URL
    }

    private struct JobUpdate {
        let job: MCPExportJobResponse
        let status: String
        let currentProjectID: UUID?
        let pendingProjectIDs: [UUID]
        let completed: [MCPExportJobResponse.CompletedExport]
        let failed: [MCPExportJobResponse.FailedExport]
    }

    struct MakeExportRequest {
        let project: RecordingProject
        let outputDirectory: URL
    }

    private struct ExportProfileRequest {
        let project: RecordingProject
        let sourceResolution: OutputResolution
    }

    private let coordinator: RecorderCoordinator
    private let fileStore: TakeFileStore
    private let transcriptStore: TranscriptArtifactStore
    private var jobs: [UUID: MCPExportJobResponse] = [:]
    private var activeExportTask: Task<Void, Never>?

    init(coordinator: RecorderCoordinator) {
        self.coordinator = coordinator
        fileStore = TakeFileStore()
        transcriptStore = TranscriptArtifactStore()
    }

    func listProjects(_ request: MCPProjectListRequest) -> MCPProjectsResponse {
        let projects = projectEntries().map { entry in
            let project = try? loadProject(entry)
            let hasTranscript = project.map { project in
                FileManager.default.fileExists(
                    atPath: transcriptStore.locations(for: project).jsonURL.path
                )
            } ?? false
            let requiredSources = project.map(requiredCaptureSources) ?? []
            let missingCaptureSourceRoles = requiredSources
                .filter { !FileManager.default.fileExists(atPath: $0.path) }
                .map(\.role)
                .sorted()
            return MCPProjectSummary(
                id: entry.id,
                title: entry.displayTitle,
                recordedAt: entry.recordedAt,
                updatedAt: entry.updatedAt,
                sourceResolution: project?.settings.outputResolution,
                sourceFramesPerSecond: project?.settings.framesPerSecond,
                captureSourceRoles: requiredSources.map(\.role).sorted(),
                missingCaptureSourceRoles: missingCaptureSourceRoles,
                canExport: project != nil && missingCaptureSourceRoles.isEmpty,
                hasTranscript: hasTranscript,
                exportCount: project?.exports.count ?? entry.exports?.count ?? 0
            )
        }
        .filter { project in
            if let query = request.query,
               !project.title.localizedCaseInsensitiveContains(query) {
                return false
            }
            if let recordedAfter = request.recordedAfter, project.recordedAt < recordedAfter {
                return false
            }
            if let recordedBefore = request.recordedBefore, project.recordedAt >= recordedBefore {
                return false
            }
            if let hasTranscript = request.hasTranscript,
               project.hasTranscript != hasTranscript {
                return false
            }
            return true
        }
        .sorted { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt {
                return lhs.recordedAt > rhs.recordedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let selected = Array(projects.dropFirst(request.offset).prefix(request.limit))
        return MCPProjectsResponse(
            projects: selected,
            totalMatched: projects.count,
            returned: selected.count,
            offset: request.offset
        )
    }

    func projectDetails(projectID: UUID) throws -> MCPProjectDetailsResponse {
        let selectedProject = try selectedProject(id: projectID)
        let project = selectedProject.project
        let requiredSources = requiredCaptureSources(project)
        let missingCaptureSourceRoles = requiredSources
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.role)
            .sorted()
        let profile = exportProfile(.init(
            project: project,
            sourceResolution: OutputResolution(rawValue: project.settings.outputResolution) ?? .p1080
        ))
        let hasTranscript = FileManager.default.fileExists(
            atPath: transcriptStore.locations(for: project).jsonURL.path
        )
        return MCPProjectDetailsResponse(
            id: project.id,
            title: selectedProject.entry.displayTitle,
            recordedAt: selectedProject.entry.recordedAt,
            updatedAt: project.updatedAt,
            sourceResolution: project.settings.outputResolution,
            sourceFramesPerSecond: project.settings.framesPerSecond,
            sources: requiredSources.map { source in
                .init(
                    role: source.role,
                    path: source.path,
                    exists: source.exists && FileManager.default.fileExists(atPath: source.path)
                )
            },
            missingCaptureSourceRoles: missingCaptureSourceRoles,
            canExport: missingCaptureSourceRoles.isEmpty,
            hasTranscript: hasTranscript,
            exportRecipe: .init(
                format: OutputVideoFormat.mp4.rawValue,
                resolution: profile.resolution.rawValue,
                framesPerSecond: profile.framesPerSecond,
                quality: profile.videoQuality.rawValue
            ),
            exports: project.exports.sorted { $0.createdAt > $1.createdAt }.map { export in
                .init(
                    id: export.id,
                    createdAt: export.createdAt,
                    path: export.path,
                    exists: FileManager.default.fileExists(atPath: export.path),
                    format: export.format,
                    resolution: export.resolution,
                    framesPerSecond: export.framesPerSecond,
                    quality: export.quality,
                    fileSizeBytes: export.fileSizeBytes
                )
            }
        )
    }

    func transcript(_ request: MCPTranscriptRequest) throws -> MCPTranscriptResponse {
        let selectedProject = try selectedProject(id: request.projectID)
        let transcriptURL = transcriptStore.locations(for: selectedProject.project).jsonURL
        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            throw MCPProjectServiceError.transcriptNotFound(request.projectID)
        }
        let transcript = try transcriptStore.load(from: transcriptURL)
        return MCPTranscriptResponse(
            projectID: request.projectID,
            title: selectedProject.entry.displayTitle,
            duration: transcript.duration,
            wordCount: transcript.wordCount,
            speakerCount: transcript.speakerCount,
            transcript: transcript.formattedText
        )
    }

    func startExport(_ request: MCPExportStartRequest) throws -> MCPExportJobResponse {
        guard !request.projectIDs.isEmpty else {
            throw MCPProjectServiceError.emptyProjectSelection
        }
        guard activeExportTask == nil else {
            throw MCPProjectServiceError.exportAlreadyRunning
        }
        let outputDirectory = try resolveOutputDirectory(request.outputDirectory)

        var seen = Set<UUID>()
        let projects = try request.projectIDs.compactMap { id -> SelectedProject? in
            guard seen.insert(id).inserted else { return nil }
            return try selectedProject(id: id)
        }
        let jobID = UUID()
        let response = MCPExportJobResponse(
            jobID: jobID,
            status: "queued",
            outputDirectory: outputDirectory.path,
            projectCount: projects.count,
            currentProjectID: nil,
            pendingProjectIDs: projects.map(\.project.id),
            completed: [],
            failed: []
        )
        jobs[jobID] = response
        activeExportTask = Task { @MainActor [weak self] in
            await self?.runJob(.init(
                jobID: jobID,
                projects: projects,
                outputDirectory: outputDirectory
            ))
        }
        return response
    }

    func exportStatus(jobID: UUID) throws -> MCPExportJobResponse {
        guard let job = jobs[jobID] else {
            throw MCPProjectServiceError.exportJobNotFound(jobID)
        }
        return job
    }

    func makeExportRequest(_ request: MakeExportRequest) throws -> ProjectExportRequest {
        let project = request.project
        let sourceResolution = OutputResolution(rawValue: project.settings.outputResolution) ?? .p1080
        let profile = exportProfile(.init(
            project: project,
            sourceResolution: sourceResolution
        ))
        if profile.resolution == .p2160, !coordinator.accessController.canUse4KExport {
            throw MCPProjectServiceError.unavailable4KExport(project.id)
        }
        let destinationURL = coordinator.uniqueOutputURL(
            request.outputDirectory
                .appendingPathComponent(ProjectExportFilename.slug(from: project.title))
                .appendingPathExtension(OutputVideoFormat.mp4.fileExtension)
        )
        return ProjectExportRequest(
            projectURL: URL(fileURLWithPath: project.projectPath),
            outputFormat: .mp4,
            performanceProfile: profile,
            destinationURL: destinationURL,
            hiddenVideoSources: Set(
                project.editorState.hiddenVideoSources.compactMap(SceneLayerKind.init(rawValue:))
            ),
            mutedAudioSources: Set(
                project.editorState.mutedAudioSources.compactMap(CaptureSource.init(rawValue:))
            ),
            backgroundMusic: backgroundMusic(project.editorState)
        )
    }

    private func runJob(_ request: RunJobRequest) async {
        guard var job = jobs[request.jobID] else { return }
        job = response(.init(
            job: job,
            status: "running",
            currentProjectID: nil,
            pendingProjectIDs: job.pendingProjectIDs,
            completed: job.completed,
            failed: job.failed
        ))
        jobs[request.jobID] = job

        for selectedProject in request.projects {
            guard !Task.isCancelled else { break }
            let pendingProjectIDs = job.pendingProjectIDs.filter {
                $0 != selectedProject.project.id
            }
            job = response(.init(
                job: job,
                status: "running",
                currentProjectID: selectedProject.project.id,
                pendingProjectIDs: pendingProjectIDs,
                completed: job.completed,
                failed: job.failed
            ))
            jobs[request.jobID] = job
            do {
                let exportRequest = try makeExportRequest(.init(
                    project: selectedProject.project,
                    outputDirectory: request.outputDirectory
                ))
                let output = try await coordinator.exportProjectForAgent(exportRequest)
                var completed = job.completed
                completed.append(.init(
                    projectID: selectedProject.project.id,
                    title: selectedProject.entry.displayTitle,
                    path: output.url.path
                ))
                job = response(.init(
                    job: job,
                    status: job.status,
                    currentProjectID: nil,
                    pendingProjectIDs: job.pendingProjectIDs,
                    completed: completed,
                    failed: job.failed
                ))
            } catch {
                var failed = job.failed
                failed.append(.init(
                    projectID: selectedProject.project.id,
                    title: selectedProject.entry.displayTitle,
                    error: error.localizedDescription
                ))
                job = response(.init(
                    job: job,
                    status: job.status,
                    currentProjectID: nil,
                    pendingProjectIDs: job.pendingProjectIDs,
                    completed: job.completed,
                    failed: failed
                ))
            }
            jobs[request.jobID] = job
        }

        let finalStatus = job.failed.isEmpty ? "completed" : "completed_with_errors"
        job = response(.init(
            job: job,
            status: finalStatus,
            currentProjectID: nil,
            pendingProjectIDs: job.pendingProjectIDs,
            completed: job.completed,
            failed: job.failed
        ))
        jobs[request.jobID] = job
        activeExportTask = nil
    }

    private func response(_ request: JobUpdate) -> MCPExportJobResponse {
        MCPExportJobResponse(
            jobID: request.job.jobID,
            status: request.status,
            outputDirectory: request.job.outputDirectory,
            projectCount: request.job.projectCount,
            currentProjectID: request.currentProjectID,
            pendingProjectIDs: request.pendingProjectIDs,
            completed: request.completed,
            failed: request.failed
        )
    }

    func resolveOutputDirectory(_ requestedDirectory: URL?) throws -> URL {
        let configuredDirectory = coordinator.settings.outputDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard let requestedDirectory else {
            return configuredDirectory
        }
        let resolvedDirectory = requestedDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let configuredPath = configuredDirectory.path
        let requestedPath = resolvedDirectory.path
        guard requestedPath == configuredPath
                || requestedPath.hasPrefix(configuredPath + "/") else {
            throw MCPProjectServiceError.outputDirectoryNotAuthorized(
                requested: requestedPath,
                configured: configuredPath
            )
        }
        let access = try fileStore.prepareOutputDirectory(settings: coordinator.settings)
        defer { access.stop() }
        try FileManager.default.createDirectory(
            at: resolvedDirectory,
            withIntermediateDirectories: true
        )
        return resolvedDirectory
    }

    private func projectEntries() -> [RecordingProjectHistory.Entry] {
        fileStore.loadProjectHistory(settings: coordinator.settings).entries
    }

    private func requiredCaptureSources(
        _ project: RecordingProject
    ) -> [RecordingProject.SourceFile] {
        let enabledSources = Set(project.settings.enabledSources)
        return project.sources.filter { source in
            guard let rawValue = captureSourceRawValue(role: source.role) else { return false }
            return enabledSources.contains(rawValue)
        }
    }

    private func captureSourceRawValue(role: String) -> String? {
        switch role {
        case "screen": CaptureSource.screen.rawValue
        case "camera": CaptureSource.camera.rawValue
        case "microphone": CaptureSource.microphone.rawValue
        case "systemAudio": CaptureSource.systemAudio.rawValue
        default: nil
        }
    }

    private func selectedProject(id: UUID) throws -> SelectedProject {
        guard let entry = projectEntries().first(where: { $0.id == id }) else {
            throw MCPProjectServiceError.projectNotFound(id)
        }
        return SelectedProject(entry: entry, project: try loadProject(entry))
    }

    private func loadProject(_ entry: RecordingProjectHistory.Entry) throws -> RecordingProject {
        try fileStore.loadRecordingProject(at: URL(fileURLWithPath: entry.projectPath))
    }

    private func exportProfile(_ request: ExportProfileRequest) -> ExportPerformanceProfile {
        let project = request.project
        guard let recipe = project.editorState.exportRecipe,
              let preset = ExportPerformancePreset(rawValue: recipe.preset),
              let resolution = OutputResolution(rawValue: recipe.resolution),
              let quality = ExportVideoQuality(rawValue: recipe.quality) else {
            return ExportPerformanceProfile(
                preset: .custom,
                resolution: request.sourceResolution,
                framesPerSecond: project.settings.framesPerSecond,
                videoQuality: .high
            )
        }
        return ExportPerformanceProfile.resolved(
            preset: preset,
            sourceResolution: request.sourceResolution,
            sourceFramesPerSecond: project.settings.framesPerSecond,
            customResolution: resolution,
            customFramesPerSecond: recipe.framesPerSecond,
            customVideoQuality: quality
        )
    }

    private func backgroundMusic(
        _ state: RecordingProject.EditorStateSnapshot
    ) -> ExportBackgroundMusic? {
        guard let path = state.backgroundMusicPath else { return nil }
        var url = URL(fileURLWithPath: path)
        if let bookmarkData = state.backgroundMusicBookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                url = resolvedURL
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ExportBackgroundMusic(url: url, volume: state.backgroundMusicVolume ?? 0.18)
    }
}
