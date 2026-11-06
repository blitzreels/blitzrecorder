import Foundation
import Observation

@Observable
@MainActor
final class LocalTranscriptionController {
    struct Dependencies {
        let engine: any LocalTranscriptionEngineServing
        let modelStore: any LocalTranscriptionModelStoring
        let artifactStore: TranscriptArtifactStore
        let fileStore: TakeFileStore
        let defaults: UserDefaults

        static let live = Dependencies(
            engine: LocalTranscriptionEngine(),
            modelStore: LocalTranscriptionModelStore(),
            artifactStore: TranscriptArtifactStore(),
            fileStore: TakeFileStore(),
            defaults: .standard
        )
    }

    private struct EnqueueRequest {
        let source: TranscriptionMediaSource
        let force: Bool
        let isUrgent: Bool
    }

    private struct QueuedJob {
        let source: TranscriptionMediaSource
        let isUrgent: Bool
        let order: Date

        func runsBefore(_ other: QueuedJob) -> Bool {
            (isUrgent ? 1 : 0, order) > (other.isUrgent ? 1 : 0, other.order)
        }
    }

    private struct AutomaticFailure: Codable {
        var count: Int
        var message: String
    }

    private struct UpdateRequest {
        let update: TranscriptionEngineUpdate
        let source: TranscriptionMediaSource
        let jobID: UUID
    }

    private struct ModelUpdateRequest {
        let update: TranscriptionModelDownloadUpdate
        let model: TranscriptionSpeechModel
    }

    private static let automaticKey = "transcription.automatic.enabled"
    private static let modelKey = "transcription.speech.model"
    private static let languageKey = "transcription.language"
    private static let speakerCountKey = "transcription.speaker-count"
    private static let failuresKey = "transcription.automatic.failures"
    private static let titleAttemptsKey = "transcription.title.attempts"
    private static let automaticAttemptLimit = 2
    private static let titleBackfillAge: TimeInterval = 7 * 86_400

    var modelStates: [TranscriptionSpeechModel: TranscriptionModelState]
    var modelState: TranscriptionModelState {
        modelStates[selectedModel] ?? .notDownloaded
    }
    var selectedModel: TranscriptionSpeechModel {
        didSet {
            defaults.set(selectedModel.rawValue, forKey: Self.modelKey)
            enqueueKnownSources()
        }
    }
    var selectedLanguage: TranscriptionLanguage {
        didSet { defaults.set(selectedLanguage.rawValue, forKey: Self.languageKey) }
    }
    var speakerCount: TranscriptionSpeakerCount {
        didSet { defaults.set(speakerCount.rawValue, forKey: Self.speakerCountKey) }
    }
    var jobStatuses: [String: TranscriptionJobStatus] = [:]
    private(set) var jobDetails: [String: String] = [:]
    private(set) var speakerFixDetails: [String: String] = [:]
    private(set) var jobStartedAt: [String: Date] = [:]
    @ObservationIgnored private var jobIDs: [String: UUID] = [:]
    struct CompletionHandler {
        weak var owner: AnyObject?
        let handle: (CompletedTranscription) -> Void
    }

    /// Every window registers; a completion goes to the first one still open, so it is handled exactly once.
    @ObservationIgnored private var completionHandlers: [CompletionHandler] = []

    func addCompletionHandler(_ handler: CompletionHandler) {
        completionHandlers.append(handler)
    }

    func deliverCompletion(_ completion: CompletedTranscription) {
        completionHandlers.removeAll { $0.owner == nil }
        completionHandlers.first?.handle(completion)
    }
    var isAutomaticEnabled: Bool {
        didSet {
            defaults.set(isAutomaticEnabled, forKey: Self.automaticKey)
            if isAutomaticEnabled {
                enqueueKnownSources()
            }
        }
    }

    @ObservationIgnored private let engine: any LocalTranscriptionEngineServing
    @ObservationIgnored private let modelStore: any LocalTranscriptionModelStoring
    @ObservationIgnored private let artifactStore: TranscriptArtifactStore
    @ObservationIgnored private let fileStore: TakeFileStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var knownSources: [String: TranscriptionMediaSource] = [:]
    @ObservationIgnored private var pendingManualSources: [String: TranscriptionMediaSource] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var inspectionTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var inspectionRequests: [String: EnqueueRequest] = [:]
    @ObservationIgnored private var sourceInspections: [String: SourceInspection] = [:]
    @ObservationIgnored private var projectSyncTask: Task<Void, Never>?
    @ObservationIgnored private var queue: [String: QueuedJob] = [:]
    @ObservationIgnored private var runningJob: QueuedJob?
    @ObservationIgnored private var sourceDates: [String: Date] = [:]
    @ObservationIgnored var onTranscriptSaved: ((TranscriptionMediaSource) -> Void)?

    var isCaptureActive = false {
        didSet {
            guard isCaptureActive != oldValue else { return }
            if isCaptureActive {
                if let key = runningJob?.source.key { tasks[key]?.cancel() }
            } else {
                pump()
            }
        }
    }

    private struct SourceInspection: Sendable {
        let transcriptURL: URL?
        let hasTranscript: Bool
        let hasNoAudio: Bool
    }

    private struct InspectionRequest {
        let source: TranscriptionMediaSource
        let fileStore: TakeFileStore
        let artifactStore: TranscriptArtifactStore
    }

    nonisolated private static func inspect(_ request: InspectionRequest) -> SourceInspection {
        let url: URL?
        var hasNoAudio = false
        switch request.source {
        case .recording(let recordingURL):
            url = request.artifactStore.locations(for: recordingURL).jsonURL
        case .project(let projectURL):
            let project = try? request.fileStore.loadRecordingProject(at: projectURL)
            url = project.map { request.artifactStore.locations(for: $0).jsonURL }
            if let project, VideoProjectImporter.Metadata.load(for: project) != nil {
                hasNoAudio = !project.sources.contains {
                    ["microphone", "systemAudio"].contains($0.role) && $0.exists
                }
            }
        }
        return SourceInspection(transcriptURL: url,
            hasTranscript: url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
            hasNoAudio: hasNoAudio)
    }

    private func inspectSource(_ source: TranscriptionMediaSource) async -> SourceInspection {
        let request = InspectionRequest(source: source, fileStore: fileStore, artifactStore: artifactStore)
        let task = Task.detached(priority: .utility) { Self.inspect(request) }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    init(_ dependencies: Dependencies = .live) {
        self.engine = dependencies.engine
        self.modelStore = dependencies.modelStore
        self.artifactStore = dependencies.artifactStore
        self.fileStore = dependencies.fileStore
        self.defaults = dependencies.defaults
        self.isAutomaticEnabled = dependencies.defaults.object(
            forKey: Self.automaticKey
        ) == nil
            ? true
            : dependencies.defaults.bool(forKey: Self.automaticKey)
        self.selectedModel = TranscriptionSpeechModel(
            rawValue: dependencies.defaults.string(forKey: Self.modelKey) ?? ""
        ) ?? .parakeet
        self.selectedLanguage = TranscriptionLanguage(
            rawValue: dependencies.defaults.string(forKey: Self.languageKey) ?? ""
        ) ?? .automatic
        self.speakerCount = TranscriptionSpeakerCount(
            rawValue: dependencies.defaults.string(forKey: Self.speakerCountKey) ?? ""
        ) ?? .automatic
        self.modelStates = Dictionary(uniqueKeysWithValues: TranscriptionSpeechModel.allCases.map { model in
            (model, dependencies.modelStore.isInstalled(model)
                ? .ready(size: dependencies.modelStore.installedSize(model))
                : .notDownloaded)
        })
        Task.detached(priority: .utility) { TranscriptionScratch.removeLeftovers() }
    }

    func downloadModels() {
        let model = selectedModel
        guard !(modelStates[model] ?? .notDownloaded).isReady else { return }
        if case .downloading = modelStates[model] {
            return
        }
        modelStates[model] = .downloading(progress: 0, phase: "Starting")
        Task {
            do {
                try await engine.downloadModels(
                    LocalTranscriptionEngine.DownloadRequest(
                        model: model,
                        onUpdate: { [weak self] update in
                            Task { @MainActor in
                                self?.applyModelDownloadUpdate(.init(update: update, model: model))
                            }
                        }
                    )
                )
                modelStates[model] = .ready(size: modelStore.installedSize(model))
                enqueuePendingManualSources()
                enqueueKnownSources()
            } catch {
                modelStates[model] = .failed(error.localizedDescription)
            }
        }
    }

    func removeModels() {
        guard !jobStatuses.values.contains(where: \.isRunning) else { return }
        let model = selectedModel
        Task {
            do {
                try await engine.removeModels(model)
                modelStates[model] = .notDownloaded
                for key in knownSources.keys {
                    if !isTranscriptReady(key) {
                        jobStatuses[key] = .waitingForModel
                    }
                }
            } catch {
                modelStates[model] = .failed(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func syncProjects(_ projects: [RecordingProjectHistory.Entry]) -> Task<Void, Never> {
        projectSyncTask?.cancel()
        let sources = projects.map { TranscriptionMediaSource.project(URL(fileURLWithPath: $0.projectPath)) }
        for source in sources { knownSources[source.key] = source }
        for project in projects { sourceDates[project.projectPath] = project.createdAt ?? project.updatedAt }
        let previousStatuses = jobStatuses
        let fileStore = fileStore
        let artifactStore = artifactStore
        let task = Task { [weak self] in
            let scan = Task.detached(priority: .utility) {
                var inspections: [String: SourceInspection] = [:]
                for source in sources {
                    guard !Task.isCancelled else { break }
                    inspections[source.key] = Self.inspect(.init(
                        source: source, fileStore: fileStore, artifactStore: artifactStore))
                }
                return inspections
            }
            let inspections = await withTaskCancellationHandler {
                await scan.value
            } onCancel: {
                scan.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            var statuses = self.jobStatuses
            for (key, inspection) in inspections {
                guard self.tasks[key] == nil, self.inspectionTasks[key] == nil,
                      statuses[key] == previousStatuses[key] else { continue }
                self.sourceInspections[key] = inspection
                if inspection.hasTranscript, let url = inspection.transcriptURL {
                    statuses[key] = .ready(url)
                } else if inspection.hasNoAudio {
                    statuses[key] = .noAudio
                } else if !self.modelState.isReady {
                    statuses[key] = .waitingForModel
                } else if case .ready = statuses[key] {
                    statuses[key] = .notGenerated
                }
            }
            if statuses != self.jobStatuses { self.jobStatuses = statuses }
            if self.isAutomaticEnabled {
                self.enqueueKnownSources()
                self.titleUntitledProjects(projects)
            }
        }
        projectSyncTask = task
        return task
    }

    func enqueueProject(_ projectURL: URL) {
        enqueue(EnqueueRequest(source: .project(projectURL), force: false, isUrgent: true))
    }

    func prioritize(_ projectURL: URL) {
        enqueue(EnqueueRequest(source: .project(projectURL), force: true, isUrgent: true))
    }

    func retry(_ source: TranscriptionMediaSource) {
        enqueue(EnqueueRequest(source: source, force: true, isUrgent: true))
    }

    func isFixingSpeakers(_ project: RecordingProjectHistory.Entry) -> Bool {
        speakerFixDetails[project.projectPath] != nil
    }

    func isUpdatingTranscript(_ project: RecordingProjectHistory.Entry) -> Bool {
        tasks[project.projectPath] != nil || inspectionTasks[project.projectPath] != nil || isFixingSpeakers(project)
    }

    func canFixSpeakers(_ project: RecordingProjectHistory.Entry) -> Bool {
        !isUpdatingTranscript(project) && modelStates.values.contains(where: \.isReady)
    }

    func beginSpeakerEdit(_ project: RecordingProjectHistory.Entry) throws {
        guard !isUpdatingTranscript(project) else { throw LocalTranscriptionError.transcriptBusy }
        speakerFixDetails[project.projectPath] = "Saving speaker"
    }

    func endSpeakerEdit(_ project: RecordingProjectHistory.Entry) {
        speakerFixDetails[project.projectPath] = nil
        pump()
    }

    func fixSpeakers(_ project: RecordingProjectHistory.Entry) async throws -> RecordingTranscript {
        let key = project.projectPath
        guard !isUpdatingTranscript(project) else { throw LocalTranscriptionError.transcriptBusy }
        guard canFixSpeakers(project) else { throw LocalTranscriptionError.modelNotInstalled }
        speakerFixDetails[key] = TranscriptionJobStatus.preparingAudio.label
        defer {
            speakerFixDetails[key] = nil
            pump()
        }
        return try await engine.reassignSpeakers(LocalTranscriptionEngine.SpeakerFixRequest(
            source: .project(URL(fileURLWithPath: key)),
            speakerCount: speakerCount,
            onUpdate: { [weak self] update in
                Task { @MainActor in
                    guard let self, self.speakerFixDetails[key] != nil else { return }
                    self.speakerFixDetails[key] = SpeakerFixProgress.label(update)
                }
            }
        ))
    }

    func status(for project: RecordingProjectHistory.Entry) -> TranscriptionJobStatus {
        jobStatuses[project.projectPath] ?? .notGenerated
    }

    private func enqueue(_ request: EnqueueRequest) {
        let source = request.source
        knownSources[source.key] = source
        guard tasks[source.key] == nil, speakerFixDetails[source.key] == nil,
              isAutomaticEnabled || request.force else { return }
        guard let inspection = sourceInspections[source.key] else {
            let earlier = inspectionRequests[source.key]
            inspectionRequests[source.key] = .init(source: source,
                force: request.force || earlier?.force == true,
                isUrgent: request.isUrgent || earlier?.isUrgent == true)
            guard inspectionTasks[source.key] == nil else { return }
            inspectionTasks[source.key] = Task { [weak self] in
                guard let self else { return }
                let inspection = await self.inspectSource(source)
                self.inspectionTasks[source.key] = nil
                let pending = self.inspectionRequests.removeValue(forKey: source.key) ?? request
                guard !Task.isCancelled else { return }
                self.sourceInspections[source.key] = inspection
                if inspection.hasTranscript, let url = inspection.transcriptURL {
                    self.jobStatuses[source.key] = .ready(url)
                }
                self.enqueue(pending)
            }
            return
        }
        if inspection.hasNoAudio {
            jobStatuses[source.key] = .noAudio
            return
        }
        if !request.force, isTranscriptReady(source.key) {
            return
        }
        if !request.force, let failure = automaticFailures[source.key],
           failure.count >= Self.automaticAttemptLimit {
            jobStatuses[source.key] = .failed(failure.message)
            return
        }
        guard modelState.isReady else {
            jobStatuses[source.key] = .waitingForModel
            if request.force {
                pendingManualSources[source.key] = source
                downloadModels()
            }
            return
        }
        pendingManualSources[source.key] = nil
        let isUrgent = request.isUrgent || queue[source.key]?.isUrgent == true
        queue[source.key] = QueuedJob(source: source, isUrgent: isUrgent,
            order: request.isUrgent ? Date() : queue[source.key]?.order ?? sourceDates[source.key] ?? .distantPast)
        jobStatuses[source.key] = .queued
        pump()
    }

    private func pump() {
        guard runningJob == nil, !isCaptureActive, modelState.isReady else { return }
        let next = queue.values
            .filter { speakerFixDetails[$0.source.key] == nil }
            .reduce(nil as QueuedJob?) { best, job in best.map { job.runsBefore($0) ? job : $0 } ?? job }
        guard let next else { return }
        queue[next.source.key] = nil
        run(next)
    }

    private func run(_ job: QueuedJob) {
        let source = job.source
        let key = source.key
        runningJob = job
        let jobID = UUID()
        jobIDs[key] = jobID
        jobStartedAt[key] = Date()
        jobDetails[key] = nil
        let model = selectedModel
        let language = selectedLanguage
        let speakerCount = speakerCount
        tasks[key] = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = try await engine.transcribe(
                    LocalTranscriptionEngine.TranscribeRequest(
                        source: source,
                        model: model,
                        language: language,
                        speakerCount: speakerCount,
                        onUpdate: { [weak self] update in
                            Task { @MainActor in
                                self?.apply(UpdateRequest(
                                    update: update,
                                    source: source,
                                    jobID: jobID
                                ))
                            }
                        }
                    )
                )
                updateFailures { $0[key] = nil }
                await markReady(source)
                onTranscriptSaved?(source)
                deliverCompletion(CompletedTranscription(source: source, transcript: transcript))
            } catch let error where Task.isCancelled || error is CancellationError {
                queue[key] = job
                jobStatuses[key] = .queued
            } catch {
                recordFailure(.init(key: key, error: error))
                jobStatuses[key] = .failed(error.localizedDescription)
            }
            tasks[key] = nil
            jobIDs[key] = nil
            jobStartedAt[key] = nil
            jobDetails[key] = nil
            runningJob = nil
            pump()
        }
    }

    private struct FailureRecord {
        let key: String
        let error: Error
    }

    private var automaticFailures: [String: AutomaticFailure] {
        defaults.data(forKey: Self.failuresKey)
            .flatMap { try? JSONDecoder().decode([String: AutomaticFailure].self, from: $0) } ?? [:]
    }

    private func updateFailures(_ change: (inout [String: AutomaticFailure]) -> Void) {
        var failures = automaticFailures
        change(&failures)
        if failures.isEmpty {
            defaults.removeObject(forKey: Self.failuresKey)
        } else if let data = try? JSONEncoder().encode(failures) {
            defaults.set(data, forKey: Self.failuresKey)
        }
    }

    private func recordFailure(_ record: FailureRecord) {
        if case LocalTranscriptionError.notEnoughSpace = record.error { return }
        updateFailures { failures in
            let count = (failures[record.key]?.count ?? 0) + 1
            failures[record.key] = AutomaticFailure(count: count, message: record.error.localizedDescription)
        }
    }

    func markTitleAttempted(_ key: String) {
        var attempted = defaults.stringArray(forKey: Self.titleAttemptsKey) ?? []
        guard !attempted.contains(key) else { return }
        attempted.append(key)
        defaults.set(Array(attempted.suffix(500)), forKey: Self.titleAttemptsKey)
    }

    private func titleUntitledProjects(_ projects: [RecordingProjectHistory.Entry]) {
        let attempted = Set(defaults.stringArray(forKey: Self.titleAttemptsKey) ?? [])
        let recent = Date().addingTimeInterval(-Self.titleBackfillAge)
        for project in projects where (project.createdAt ?? project.updatedAt) > recent
            && !attempted.contains(project.projectPath)
            && (RecordingProjectDisplayTitle.isUntitled(project.title)
                || ProjectFolderTitle.untitledPrefix(project.title) != nil) {
            guard tasks[project.projectPath] == nil,
                  let inspection = sourceInspections[project.projectPath], inspection.hasTranscript,
                  let transcriptURL = inspection.transcriptURL else { continue }
            let source = TranscriptionMediaSource.project(URL(fileURLWithPath: project.projectPath))
            Task { [weak self] in
                let transcript = await Task.detached(priority: .utility) {
                    try? TranscriptArtifactStore().load(from: transcriptURL)
                }.value
                guard let self, let transcript else { return }
                self.deliverCompletion(CompletedTranscription(source: source, transcript: transcript))
            }
        }
    }

    private func enqueueKnownSources() {
        for source in knownSources.values {
            enqueue(EnqueueRequest(source: source, force: false, isUrgent: false))
        }
    }

    private func enqueuePendingManualSources() {
        let sources = Array(pendingManualSources.values)
        for source in sources {
            enqueue(EnqueueRequest(source: source, force: true, isUrgent: true))
        }
    }

    private func applyModelDownloadUpdate(_ request: ModelUpdateRequest) {
        guard case .downloading = modelStates[request.model] else { return }
        modelStates[request.model] = .downloading(
            progress: request.update.fractionCompleted,
            phase: request.update.phase
        )
    }

    private func markReady(_ source: TranscriptionMediaSource) async {
        let inspection = await inspectSource(source)
        sourceInspections[source.key] = inspection
        guard let transcriptURL = inspection.transcriptURL else {
            jobStatuses[source.key] = .failed(
                LocalTranscriptionError.transcriptUnavailable.localizedDescription
            )
            return
        }
        jobStatuses[source.key] = .ready(transcriptURL)
    }

    private func isTranscriptReady(_ key: String) -> Bool {
        if case .ready = jobStatuses[key] {
            return true
        }
        return false
    }

    private func apply(_ request: UpdateRequest) {
        guard jobIDs[request.source.key] == request.jobID else { return }
        jobDetails[request.source.key] = request.update.detail
        switch request.update.stage {
        case .preparingAudio:
            jobStatuses[request.source.key] = .preparingAudio
        case .loadingModels:
            jobStatuses[request.source.key] = .loadingModels
        case .transcribing:
            jobStatuses[request.source.key] = .transcribing
        case .diarizing:
            jobStatuses[request.source.key] = .diarizing
        case .saving:
            jobStatuses[request.source.key] = .saving
        }
    }
}
