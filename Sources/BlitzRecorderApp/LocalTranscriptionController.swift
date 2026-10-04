import Foundation
import Observation

protocol LocalTranscriptionEngineServing: Sendable {
    func downloadModels(
        _ request: LocalTranscriptionEngine.DownloadRequest
    ) async throws
    func transcribe(
        _ request: LocalTranscriptionEngine.TranscribeRequest
    ) async throws -> RecordingTranscript
    func reassignSpeakers(
        _ request: LocalTranscriptionEngine.SpeakerFixRequest
    ) async throws -> RecordingTranscript
    func removeModels(_ model: TranscriptionSpeechModel) async throws
}

protocol LocalTranscriptionModelStoring: Sendable {
    func isInstalled(_ model: TranscriptionSpeechModel) -> Bool
    func installedSize(_ model: TranscriptionSpeechModel) -> Int64
}

enum TranscriptionSpeechModel: String, CaseIterable, Sendable {
    case parakeet
    case whisperMedium
    case whisperLargeTurbo
    case whisperLarge

    /// WhisperKit repo id. Nil for the Parakeet ASR model.
    var whisperVariant: String? {
        switch self {
        case .parakeet: nil
        case .whisperMedium: "openai_whisper-medium"
        case .whisperLargeTurbo: "openai_whisper-large-v3_turbo"
        case .whisperLarge: "openai_whisper-large-v3"
        }
    }

    var title: String {
        switch self {
        case .parakeet: "Parakeet v3"
        case .whisperMedium: "Whisper Medium"
        case .whisperLargeTurbo: "Whisper Large Turbo"
        case .whisperLarge: "Whisper Large"
        }
    }

    var detail: String {
        switch self {
        case .parakeet: "Fast, multilingual; automatic language only"
        case .whisperMedium: "Multilingual; supports a language lock"
        case .whisperLargeTurbo: "Large-v3 accuracy, faster than full Large"
        case .whisperLarge: "Highest accuracy on long calls"
        }
    }

    var plainDetail: String {
        switch self {
        case .parakeet: "Fastest. Detects the language on its own."
        case .whisperMedium: "Clearer. Lets you pick the language."
        case .whisperLargeTurbo: "Much more accurate. Large download, still practical."
        case .whisperLarge: "Most accurate. Largest download and the slowest pass."
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Sendable {
    case automatic
    case french
    case english

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .french: "French"
        case .english: "English"
        }
    }

    var whisperCode: String? {
        switch self {
        case .automatic: nil
        case .french: "fr"
        case .english: "en"
        }
    }
}

enum TranscriptionSpeakerCount: String, CaseIterable, Sendable {
    case automatic
    case two

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .two: "2 speakers"
        }
    }
}

enum TranscriptionModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double, phase: String)
    case ready(size: Int64)
    case failed(String)

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

enum TranscriptionJobStatus: Equatable {
    case notGenerated
    case noAudio
    case waitingForModel
    case queued
    case preparingAudio
    case loadingModels
    case transcribing
    case diarizing
    case saving
    case ready(URL)
    case failed(String)

    var label: String {
        switch self {
        case .notGenerated:
            return "Generate transcript"
        case .noAudio:
            return "No audio track"
        case .waitingForModel:
            return "Model required"
        case .queued:
            return "Queued"
        case .preparingAudio:
            return "Preparing audio"
        case .loadingModels:
            return "Loading speech model"
        case .transcribing:
            return "Transcribing"
        case .diarizing:
            return "Finding speakers"
        case .saving:
            return "Saving transcript"
        case .ready:
            return "Transcript ready"
        case .failed:
            return "Transcript failed"
        }
    }

    var isRunning: Bool {
        switch self {
        case .queued, .preparingAudio, .loadingModels, .transcribing, .diarizing, .saving:
            return true
        case .notGenerated, .noAudio, .waitingForModel, .ready, .failed:
            return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum SpeakerFixProgress {
    static func label(_ update: TranscriptionEngineUpdate) -> String {
        let stage: String
        switch update.stage {
        case .preparingAudio: stage = TranscriptionJobStatus.preparingAudio.label
        case .loadingModels: stage = "Loading speaker model"
        case .transcribing, .diarizing: stage = TranscriptionJobStatus.diarizing.label
        case .saving: stage = TranscriptionJobStatus.saving.label
        }
        guard let detail = update.detail else { return stage }
        return "\(stage) · \(detail)"
    }
}

struct CompletedTranscription {
    let source: TranscriptionMediaSource
    let transcript: RecordingTranscript
}

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
    @ObservationIgnored var onTranscriptionCompleted: ((CompletedTranscription) -> Void)?
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
        self.speakerCount = .automatic
        dependencies.defaults.removeObject(forKey: Self.speakerCountKey)
        self.modelStates = Dictionary(uniqueKeysWithValues: TranscriptionSpeechModel.allCases.map { model in
            (model, dependencies.modelStore.isInstalled(model)
                ? .ready(size: dependencies.modelStore.installedSize(model))
                : .notDownloaded)
        })
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
            if self.isAutomaticEnabled { self.enqueueKnownSources() }
        }
        projectSyncTask = task
        return task
    }

    func enqueueProject(_ projectURL: URL) {
        enqueue(EnqueueRequest(source: .project(projectURL), force: false))
    }

    func retry(_ source: TranscriptionMediaSource) {
        enqueue(EnqueueRequest(source: source, force: true))
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

    func fixSpeakers(_ project: RecordingProjectHistory.Entry) async throws -> RecordingTranscript {
        let key = project.projectPath
        guard !isUpdatingTranscript(project) else { throw LocalTranscriptionError.transcriptBusy }
        guard canFixSpeakers(project) else { throw LocalTranscriptionError.modelNotInstalled }
        speakerFixDetails[key] = TranscriptionJobStatus.preparingAudio.label
        defer { speakerFixDetails[key] = nil }
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
            inspectionRequests[source.key] = .init(source: source,
                force: request.force || inspectionRequests[source.key]?.force == true)
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
        guard isAutomaticEnabled || request.force else { return }
        guard modelState.isReady else {
            jobStatuses[source.key] = .waitingForModel
            if request.force {
                pendingManualSources[source.key] = source
                downloadModels()
            }
            return
        }
        pendingManualSources[source.key] = nil
        jobStatuses[source.key] = .queued
        let jobID = UUID()
        jobIDs[source.key] = jobID
        jobStartedAt[source.key] = Date()
        jobDetails[source.key] = nil
        let model = selectedModel
        let language = selectedLanguage
        let speakerCount = speakerCount
        tasks[source.key] = Task { [weak self] in
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
                await markReady(source)
                onTranscriptionCompleted?(CompletedTranscription(
                    source: source,
                    transcript: transcript
                ))
            } catch {
                jobStatuses[source.key] = .failed(error.localizedDescription)
            }
            tasks[source.key] = nil
            jobIDs[source.key] = nil
            jobStartedAt[source.key] = nil
            jobDetails[source.key] = nil
        }
    }

    private func enqueueKnownSources() {
        for source in knownSources.values {
            enqueue(EnqueueRequest(source: source, force: false))
        }
    }

    private func enqueuePendingManualSources() {
        let sources = Array(pendingManualSources.values)
        for source in sources {
            enqueue(EnqueueRequest(source: source, force: true))
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
