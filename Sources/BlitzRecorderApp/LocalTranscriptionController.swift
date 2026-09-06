import Foundation
import Observation

protocol LocalTranscriptionEngineServing: Sendable {
    func downloadModels(
        _ request: LocalTranscriptionEngine.DownloadRequest
    ) async throws
    func transcribe(
        _ request: LocalTranscriptionEngine.TranscribeRequest
    ) async throws -> RecordingTranscript
    func removeModels() async throws
}

protocol LocalTranscriptionModelStoring: Sendable {
    var isInstalled: Bool { get }
    var installedSize: Int64 { get }
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
    case waitingForModel
    case queued
    case preparingAudio
    case transcribing
    case diarizing
    case saving
    case ready(URL)
    case failed(String)

    var label: String {
        switch self {
        case .notGenerated:
            return "Generate transcript"
        case .waitingForModel:
            return "Model required"
        case .queued:
            return "Queued"
        case .preparingAudio:
            return "Preparing audio"
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
        case .queued, .preparingAudio, .transcribing, .diarizing, .saving:
            return true
        case .notGenerated, .waitingForModel, .ready, .failed:
            return false
        }
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
    }

    private static let automaticKey = "transcription.automatic.enabled"

    var modelState: TranscriptionModelState
    var jobStatuses: [String: TranscriptionJobStatus] = [:]
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
        self.modelState = dependencies.modelStore.isInstalled
            ? .ready(size: dependencies.modelStore.installedSize)
            : .notDownloaded
    }

    func downloadModels() {
        guard !modelState.isReady else { return }
        if case .downloading = modelState {
            return
        }
        modelState = .downloading(progress: 0, phase: "Starting")
        Task {
            do {
                try await engine.downloadModels(
                    LocalTranscriptionEngine.DownloadRequest(
                        onUpdate: { [weak self] update in
                            Task { @MainActor in
                                self?.applyModelDownloadUpdate(update)
                            }
                        }
                    )
                )
                modelState = .ready(size: modelStore.installedSize)
                enqueuePendingManualSources()
                enqueueKnownSources()
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    func removeModels() {
        guard !jobStatuses.values.contains(where: \.isRunning) else { return }
        Task {
            do {
                try await engine.removeModels()
                modelState = .notDownloaded
                for key in knownSources.keys {
                    if !isTranscriptReady(key) {
                        jobStatuses[key] = .waitingForModel
                    }
                }
            } catch {
                modelState = .failed(error.localizedDescription)
            }
        }
    }

    func syncProjects(_ projects: [RecordingProjectHistory.Entry]) {
        for project in projects {
            let source = TranscriptionMediaSource.project(
                URL(fileURLWithPath: project.projectPath)
            )
            knownSources[source.key] = source
            refreshStatus(source)
        }
        if isAutomaticEnabled {
            enqueueKnownSources()
        }
    }

    func enqueueProject(_ projectURL: URL) {
        enqueue(EnqueueRequest(source: .project(projectURL), force: false))
    }

    func retry(_ source: TranscriptionMediaSource) {
        enqueue(EnqueueRequest(source: source, force: true))
    }

    func status(for project: RecordingProjectHistory.Entry) -> TranscriptionJobStatus {
        jobStatuses[project.projectPath] ?? .notGenerated
    }

    private func enqueue(_ request: EnqueueRequest) {
        let source = request.source
        knownSources[source.key] = source
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
        guard tasks[source.key] == nil else { return }

        pendingManualSources[source.key] = nil
        jobStatuses[source.key] = .queued
        tasks[source.key] = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = try await engine.transcribe(
                    LocalTranscriptionEngine.TranscribeRequest(
                        source: source,
                        onUpdate: { [weak self] update in
                            Task { @MainActor in
                                self?.apply(UpdateRequest(
                                    update: update,
                                    source: source
                                ))
                            }
                        }
                    )
                )
                markReady(source)
                onTranscriptionCompleted?(CompletedTranscription(
                    source: source,
                    transcript: transcript
                ))
            } catch {
                jobStatuses[source.key] = .failed(error.localizedDescription)
            }
            tasks[source.key] = nil
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

    private func applyModelDownloadUpdate(
        _ update: TranscriptionModelDownloadUpdate
    ) {
        guard case .downloading = modelState else { return }
        modelState = .downloading(
            progress: update.fractionCompleted,
            phase: update.phase
        )
    }

    private func refreshStatus(_ source: TranscriptionMediaSource) {
        if let transcriptURL = transcriptURL(source),
           FileManager.default.fileExists(atPath: transcriptURL.path) {
            jobStatuses[source.key] = .ready(transcriptURL)
        } else if !modelState.isReady {
            jobStatuses[source.key] = .waitingForModel
        }
    }

    private func markReady(_ source: TranscriptionMediaSource) {
        guard let transcriptURL = transcriptURL(source) else {
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

    private func transcriptURL(_ source: TranscriptionMediaSource) -> URL? {
        switch source {
        case .recording(let recordingURL):
            return artifactStore.locations(for: recordingURL).jsonURL
        case .project(let projectURL):
            guard let project = try? fileStore.loadRecordingProject(at: projectURL) else {
                return nil
            }
            return artifactStore.locations(for: project).jsonURL
        }
    }

    private func apply(_ request: UpdateRequest) {
        switch request.update.stage {
        case .preparingAudio:
            jobStatuses[request.source.key] = .preparingAudio
        case .transcribing:
            jobStatuses[request.source.key] = .transcribing
        case .diarizing:
            jobStatuses[request.source.key] = .diarizing
        case .saving:
            jobStatuses[request.source.key] = .saving
        }
    }
}
