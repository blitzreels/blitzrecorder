import Foundation
import Observation

@MainActor @Observable
final class VoiceDiscoveryModel {
    static let shared = VoiceDiscoveryModel()

    private(set) var update: VoiceDiscoveryScanner.Update?
    private(set) var isScanning = false
    private(set) var isStopping = false
    private(set) var wasCancelled = false
    private(set) var isSaving = false
    private(set) var preparingIDs: Set<UUID> = []
    private(set) var sampleErrors: [UUID: String] = [:]
    var errorMessage: String?
    private var resolvedIDs: Set<UUID> = []
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()
    private let store: SpeakerVoiceStore

    private struct Preview {
        let sample: SpeakerSampleBuilder.Sample
        let voice: SpeakerVoice
    }

    private var previews: [UUID: Preview] = [:]

    init(store: SpeakerVoiceStore = .shared) {
        self.store = store
    }

    var voices: [DetectedVoice] {
        (update?.index.voices ?? []).filter { !resolvedIDs.contains($0.id) }
    }

    func start(_ projects: [RecordingProjectHistory.Entry]) {
        guard !isScanning, !isSaving, preparingIDs.isEmpty else { return }
        for preview in previews.values { try? FileManager.default.removeItem(at: preview.sample.url) }
        previews = [:]
        resolvedIDs = []
        errorMessage = nil
        sampleErrors = [:]
        wasCancelled = false
        isStopping = false
        isScanning = true
        generation = UUID()
        update = .init(index: VoiceDiscoveryIndex(), checked: 0, total: projects.count,
                       currentTitle: "Checking saved analysis", failures: [])
        scanTask = Task {
            defer { isScanning = false; isStopping = false; scanTask = nil }
            do {
                let profiles = try await store.profiles()
                try await VoiceDiscoveryScanner.local().scan(.init(
                    projects: projects, profiles: profiles,
                    onUpdate: { value in await self.receive(value) }
                ))
            } catch is CancellationError {
                wasCancelled = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func receive(_ value: VoiceDiscoveryScanner.Update) {
        update = value
    }

    func cancel() {
        guard isScanning else { return }
        isStopping = true
        scanTask?.cancel()
    }

    func sampleURL(_ candidate: DetectedVoice) async throws -> URL {
        do {
            let url = try await preview(candidate).sample.url
            sampleErrors[candidate.id] = nil
            return url
        } catch {
            sampleErrors[candidate.id] = "Sample unavailable. Open the recording to review this voice."
            throw error
        }
    }

    private func preview(_ candidate: DetectedVoice) async throws -> Preview {
        if let existing = previews[candidate.id] { return existing }
        guard !preparingIDs.contains(candidate.id) else { throw LocalTranscriptionError.transcriptBusy }
        let currentGeneration = generation
        preparingIDs.insert(candidate.id)
        defer { preparingIDs.remove(candidate.id) }
        for observation in candidate.observations {
            try Task.checkCancellation()
            guard let project = try? TakeFileStore().loadRecordingProject(
                at: URL(fileURLWithPath: observation.project.projectPath)
            ), let sample = try? await SpeakerSampleBuilder.shared.make(.init(
                project: project, transcript: observation.transcript, speakerID: observation.speakerID
            )) else { continue }
            guard currentGeneration == generation, !Task.isCancelled else {
                try? FileManager.default.removeItem(at: sample.url)
                throw CancellationError()
            }
            let preview = Preview(sample: .init(
                url: sample.url, sourceTitle: observation.project.displayTitle,
                sourceProjectID: sample.sourceProjectID, duration: sample.duration, text: sample.text
            ), voice: observation.voice)
            previews[candidate.id] = preview
            return preview
        }
        throw SpeakerVoiceStore.PreviewError.missingSample
    }

    struct SaveRequest {
        let candidate: DetectedVoice
        let name: String
        let profileID: UUID?
    }

    func save(_ request: SaveRequest) async -> Bool {
        guard !isScanning, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let clip = try await preview(request.candidate)
            let profiles = try await store.profiles()
            if let id = request.profileID, !profiles.contains(where: { $0.id == id }) {
                throw SpeakerVoiceStore.PreviewError.missingProfile
            }
            let name = profiles.first(where: { $0.id == request.profileID })?.name ?? request.name
            let id = try await store.remember(.init(name: name, voice: clip.voice, profileID: request.profileID))
            do {
                try await store.savePreview(.init(profileID: id, sample: clip.sample))
                errorMessage = nil
            } catch {
                errorMessage = "Speaker saved, but the sample could not be saved: \(error.localizedDescription)"
            }
            resolvedIDs.insert(request.candidate.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dismiss(_ id: UUID) {
        resolvedIDs.insert(id)
    }
}
