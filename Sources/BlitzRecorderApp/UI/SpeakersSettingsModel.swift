import AVFoundation
import Observation

@MainActor @Observable
final class SpeakersSettingsModel: NSObject, AVAudioPlayerDelegate {
    private(set) var profiles: [SavedSpeakerVoice] = []
    private(set) var availableSamples: Set<UUID> = []
    private(set) var preparingID: UUID?
    private(set) var playingID: UUID?
    private(set) var isLoaded = false
    private(set) var isSaving = false
    var errorMessage: String?
    private var player: AVAudioPlayer?
    private var playbackRequest = UUID()
    private let store: SpeakerVoiceStore

    init(store: SpeakerVoiceStore = .shared) {
        self.store = store
        super.init()
    }

    func load(_ projects: [RecordingProjectHistory.Entry]) async {
        do {
            try await reload()
            isLoaded = true
            for profile in profiles where !availableSamples.contains(profile.id) {
                try Task.checkCancellation()
                preparingID = profile.id
                defer { preparingID = nil }
                do {
                    let sample = try await SpeakerSampleBuilder.shared.find(.init(profile: profile, projects: projects))
                    defer { try? FileManager.default.removeItem(at: sample.url) }
                    try Task.checkCancellation()
                    try await store.savePreview(.init(profileID: profile.id, sample: sample))
                    try await reload()
                } catch is CancellationError {
                    return
                } catch SpeakerVoiceStore.PreviewError.missingSample {
                    continue
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch is CancellationError {
            return
        } catch {
            isLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayback(_ id: UUID) async {
        await toggleSample(.init(id: id, loadURL: { [store] in
            guard let url = try await store.sampleURL(for: id) else {
                throw SpeakerVoiceStore.PreviewError.missingSample
            }
            return url
        }))
    }

    struct PlaybackRequest {
        let id: UUID
        let loadURL: @MainActor () async throws -> URL
    }

    func toggleSample(_ sample: PlaybackRequest) async {
        let wasPlaying = playingID == sample.id
        stop()
        guard !wasPlaying else { return }
        let request = playbackRequest
        do {
            let url = try await sample.loadURL()
            guard request == playbackRequest else { return }
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            guard audio.play() else { throw PlaybackError.unavailable }
            player = audio
            playingID = sample.id
            errorMessage = nil
        } catch {
            if request == playbackRequest { errorMessage = error.localizedDescription }
        }
    }

    func refreshProfiles() async {
        do { try await reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func stop() {
        playbackRequest = UUID()
        player?.stop()
        player?.delegate = nil
        player = nil
        playingID = nil
    }

    func playbackTime(for id: UUID) -> TimeInterval {
        playingID == id ? player?.currentTime ?? 0 : 0
    }

    func rename(_ request: SpeakerVoiceStore.RenameRequest) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.rename(request)
            try await reload()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func forget(_ id: UUID) async {
        if playingID == id { stop() }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.forget(id)
            try await reload()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async throws {
        profiles = try await store.profiles().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var available: Set<UUID> = []
        for profile in profiles {
            if try await store.sampleURL(for: profile.id) != nil { available.insert(profile.id) }
        }
        availableSamples = available
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.stop()
            if !flag { self.errorMessage = PlaybackError.unavailable.localizedDescription }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }

    private enum PlaybackError: LocalizedError {
        case unavailable
        var errorDescription: String? { "This voice sample could not be played." }
    }
}
