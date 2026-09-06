import AVFoundation
import Foundation
import Observation
import SwiftUI

enum EditorProjectRefreshKind: Equatable {
    case fullPlayback
    case sceneTimeline
}

struct EditorProjectRefreshRequest {
    let hasActivePlayback: Bool
    let isSameProject: Bool
    let hasSameMedia: Bool
}

enum EditorProjectRefreshPolicy {
    static func kind(for request: EditorProjectRefreshRequest) -> EditorProjectRefreshKind {
        guard request.hasActivePlayback,
              request.isSameProject,
              request.hasSameMedia else {
            return .fullPlayback
        }
        return .sceneTimeline
    }
}

enum EditorPlaybackClockSelection {
    static func index(for durations: [Double]) -> Int? {
        guard !durations.isEmpty else { return nil }
        var selectedIndex = 0
        var selectedDuration = normalizedDuration(durations[0])
        for index in durations.indices.dropFirst() {
            let duration = normalizedDuration(durations[index])
            if duration > selectedDuration {
                selectedIndex = index
                selectedDuration = duration
            }
        }
        return selectedIndex
    }

    private static func normalizedDuration(_ duration: Double) -> Double {
        duration.isFinite ? max(0, duration) : 0
    }
}

enum EditorPlaybackRate: Float, CaseIterable, Equatable {
    case normal = 1
    case oneAndAHalf = 1.5
    case double = 2
    case twoAndAHalf = 2.5

    var displayName: String {
        switch self {
        case .normal:
            "1×"
        case .oneAndAHalf:
            "1.5×"
        case .double:
            "2×"
        case .twoAndAHalf:
            "2.5×"
        }
    }

    var nextFaster: EditorPlaybackRate {
        switch self {
        case .normal:
            .oneAndAHalf
        case .oneAndAHalf:
            .double
        case .double, .twoAndAHalf:
            .twoAndAHalf
        }
    }
}

private struct EditorPlaybackMediaSignature: Equatable {
    let version: Int
    let id: UUID
    let projectPath: String
    let takeDirectoryPath: String
    let finalVideoPath: String?
    let timelineTrimOffsetSeconds: Double
    let sourceTimelineOffsetSeconds: [String: Double]
    let settings: RecordingProject.SettingsSnapshot
    let sources: [RecordingProject.SourceFile]

    init(project: RecordingProject) {
        version = project.version
        id = project.id
        projectPath = project.projectPath
        takeDirectoryPath = project.takeDirectoryPath
        finalVideoPath = project.finalVideoPath
        timelineTrimOffsetSeconds = project.timelineTrimOffsetSeconds
        sourceTimelineOffsetSeconds = project.sourceTimelineOffsetSeconds
        settings = project.settings
        sources = project.sources
    }
}

struct EditorPlaybackSceneTimelineUpdate {
    let project: RecordingProject
    let baseSettings: RecordingSettings
    let preservesPreviewSceneOverride: Bool
}

@MainActor
@Observable
final class EditorPlaybackController {
    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isReady = false
    private(set) var loadError: String?
    private(set) var renderSize: CGSize = .zero
    private(set) var hiddenKinds: Set<SceneLayerKind> = []
    private(set) var mutedSources: Set<CaptureSource> = []
    private(set) var previewSceneRevision = 0
    private(set) var playbackRate = EditorPlaybackRate.normal

    @ObservationIgnored private var playback: EditorPlaybackComposition?
    @ObservationIgnored private var videoPlayers: [SceneLayerKind: AVPlayer] = [:]
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var audioInputs: [(source: CaptureSource, baseVolume: Float)] = []
    @ObservationIgnored private var audioMixTracks: [(source: CaptureSource, track: AVCompositionTrack, baseVolume: Float)] = []
    @ObservationIgnored private var audioComposition: AVMutableComposition?
    @ObservationIgnored private var playbackClockPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadedProjectPath: String?
    @ObservationIgnored private var loadedMediaSignature: EditorPlaybackMediaSignature?
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var previewSceneOverride: (scene: RecordingScene, time: Double)?

    var hideableKinds: Set<SceneLayerKind> {
        Set(playback?.videoKinds ?? [])
    }

    var muteableSources: Set<CaptureSource> {
        Set(playback?.audioInputs.map(\.source) ?? [])
    }

    var sourceAspectRatios: [SceneLayerKind: CGFloat] {
        playback?.sourceAspectRatios ?? [:]
    }

    func videoPlayer(for kind: SceneLayerKind) -> AVPlayer? {
        videoPlayers[kind]
    }

    private var masterPlayer: AVPlayer? {
        playbackClockPlayer
    }

    private var allPlayers: [AVPlayer] {
        var players = Array(videoPlayers.values)
        if let audioPlayer { players.append(audioPlayer) }
        return players
    }

    func load(project: RecordingProject, baseSettings: RecordingSettings) async {
        loadGeneration += 1
        let generation = loadGeneration

        let isSameProject = loadedProjectPath == project.projectPath
        let resumeTime = isSameProject ? currentTime : 0
        let wasPlaying = isSameProject && isPlaying

        pauseAll()
        isPlaying = false
        isReady = false
        loadError = nil

        let store = TakeFileStore()
        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
            ?? baseSettings.outputVideoFormat
        let settings = store.recordingSettings(from: project, baseSettings: baseSettings, outputFormat: outputFormat)
        let take = store.recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        let sceneEvents = store.sceneEvents(from: project)

        do {
            let playback = try await Merger.editorPlaybackComposition(
                take: take,
                settings: settings,
                sceneEvents: sceneEvents
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            teardownPlayers()
            self.playback = playback
            loadedProjectPath = project.projectPath
            loadedMediaSignature = EditorPlaybackMediaSignature(project: project)
            renderSize = playback.renderSize
            previewSceneOverride = nil
            previewSceneRevision &+= 1
            applyEditorState(project.editorState)

            buildPlayers(playback: playback)
            guard try await waitForPlayersReady((players: allPlayers, generation: generation)) else { return }
            let clockPlayer = await selectPlaybackClockPlayer()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            playbackClockPlayer = clockPlayer
            duration = max(0, playback.duration.seconds)
            installObservers()

            let startTime = resumeTime > 0 ? min(resumeTime, duration) : 0
            currentTime = startTime
            await seekAllPrecisely(to: startTime)

            guard generation == loadGeneration, !Task.isCancelled else { return }
            isReady = true
            if wasPlaying { isPlaying = playAll() }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            teardownPlayers()
            playback = nil
            loadedProjectPath = nil
            loadedMediaSignature = nil
            duration = 0
            renderSize = .zero
            loadError = error.localizedDescription
        }
    }

    func refreshSceneTimeline(_ update: EditorPlaybackSceneTimelineUpdate) -> Bool {
        let incomingSignature = EditorPlaybackMediaSignature(project: update.project)
        let kind = EditorProjectRefreshPolicy.kind(for: EditorProjectRefreshRequest(
            hasActivePlayback: isReady && playback != nil,
            isSameProject: loadedProjectPath == update.project.projectPath,
            hasSameMedia: loadedMediaSignature == incomingSignature
        ))
        guard kind == .sceneTimeline, let playback else { return false }

        let store = TakeFileStore()
        let outputFormat = OutputVideoFormat(rawValue: update.project.settings.outputVideoFormat)
            ?? update.baseSettings.outputVideoFormat
        let settings = store.recordingSettings(
            from: update.project,
            baseSettings: update.baseSettings,
            outputFormat: outputFormat
        )
        let sceneEvents = store.sceneEvents(from: update.project)
        guard let refreshedPlayback = try? playback.updatingSceneTimeline(EditorPlaybackSceneTimeline(
            settings: settings,
            sceneEvents: sceneEvents
        )) else {
            return false
        }

        self.playback = refreshedPlayback
        loadedMediaSignature = incomingSignature
        if !update.preservesPreviewSceneOverride {
            previewSceneOverride = nil
        }
        previewSceneRevision &+= 1
        renderSize = refreshedPlayback.renderSize
        applyPreviewDuration()
        return true
    }

    private func buildPlayers(playback: EditorPlaybackComposition) {
        for kind in playback.videoKinds {
            guard let asset = playback.videoAsset(for: kind) else { continue }
            let item = AVPlayerItem(asset: asset)
            item.audioTimePitchAlgorithm = .timeDomain
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.isMuted = true
            videoPlayers[kind] = player
        }
        buildAudioPlayer(playback: playback)
    }

    private func buildAudioPlayer(playback: EditorPlaybackComposition) {
        let inputs = playback.audioInputs
        guard !inputs.isEmpty else { return }
        let composition = AVMutableComposition()
        var mixTracks: [(source: CaptureSource, track: AVCompositionTrack, baseVolume: Float)] = []
        for input in inputs {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let range = input.track.timeRange
            guard CMTimeCompare(range.duration, .zero) > 0 else { continue }
            try? track.insertTimeRange(range, of: input.track, at: range.start)
            mixTracks.append((input.source, track, input.volume))
        }
        guard !mixTracks.isEmpty else { return }
        audioComposition = composition
        audioMixTracks = mixTracks
        let item = AVPlayerItem(asset: composition)
        item.audioTimePitchAlgorithm = .timeDomain
        item.audioMix = audioMix()
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        audioPlayer = player
    }

    private func waitForPlayersReady(_ request: (players: [AVPlayer], generation: Int)) async throws -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while true {
            guard request.generation == loadGeneration else { return false }
            try Task.checkCancellation()
            if let failed = request.players.first(where: { $0.status == .failed }) {
                throw failed.error ?? RecorderError.playbackNotReady
            }
            if !request.players.isEmpty, request.players.allSatisfy({ $0.status == .readyToPlay }) { return true }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw RecorderError.playbackNotReady }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func selectPlaybackClockPlayer() async -> AVPlayer? {
        let candidates = [audioPlayer, videoPlayers[.screen], videoPlayers[.camera]].compactMap { $0 }
        var durations: [Double] = []
        for player in candidates {
            let duration = try? await player.currentItem?.asset.load(.duration)
            durations.append(duration?.seconds ?? 0)
        }
        guard let index = EditorPlaybackClockSelection.index(for: durations) else { return nil }
        return candidates[index]
    }

    private func audioMix() -> AVAudioMix? {
        guard !audioMixTracks.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioMixTracks.map { entry in
            let params = AVMutableAudioMixInputParameters(track: entry.track)
            params.setVolume(mutedSources.contains(entry.source) ? 0 : entry.baseVolume, at: .zero)
            return params
        }
        return mix
    }

    func scene(at seconds: Double) -> RecordingScene? {
        guard let playback else { return nil }
        let segments: [FinalExportRenderSegment]
        if let previewSceneOverride {
            segments = playback.renderSegments(
                hiding: hiddenKinds,
                overriding: previewSceneOverride.scene,
                at: CMTime(seconds: previewSceneOverride.time, preferredTimescale: 600)
            )
        } else {
            segments = playback.renderSegments(hiding: hiddenKinds)
        }
        let time = CMTime(seconds: clampedTime(seconds), preferredTimescale: 600)
        let segment = segments.first { CMTimeRangeContainsTime($0.timeRange, time: time) } ?? segments.last
        return segment?.scene
    }

    func togglePlayback() {
        guard isReady, masterPlayer != nil else { return }
        if isPlaying {
            pauseAll()
            isPlaying = false
        } else {
            if duration > 0, currentTime >= duration - 0.05 {
                currentTime = 0
                seekAll(to: 0, precise: true)
            }
            isPlaying = playAll()
        }
    }

    func play(from seconds: Double) {
        guard isReady, masterPlayer != nil else { return }
        currentTime = clampedTime(seconds)
        isScrubbing = false
        isPlaying = playAll()
    }

    func setPlaybackRate(_ rate: EditorPlaybackRate) {
        guard playbackRate != rate else { return }
        playbackRate = rate
        guard isPlaying else { return }
        if let seconds = masterPlayer?.currentTime().seconds, seconds.isFinite {
            currentTime = clampedTime(seconds)
        }
        isPlaying = playAll()
    }

    func playForwardOrIncreaseRate() {
        guard isReady, masterPlayer != nil else { return }
        if !isPlaying {
            playbackRate = .normal
            togglePlayback()
            return
        }
        setPlaybackRate(playbackRate.nextFaster)
    }

    private func playAll() -> Bool {
        let players = allPlayers
        guard !players.isEmpty, players.allSatisfy({ $0.status == .readyToPlay }) else {
            pauseAll()
            isReady = false
            loadError = RecorderError.playbackNotReady.localizedDescription
            return false
        }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let hostTime = CMTimeAdd(now, CMTime(seconds: 0.06, preferredTimescale: 600))
        for player in players {
            let clamped = itemClampedTime(currentTime, for: player)
            player.setRate(
                playbackRate.rawValue,
                time: CMTime(seconds: clamped, preferredTimescale: 600),
                atHostTime: hostTime
            )
        }
        return true
    }

    private func pauseAll() {
        for player in allPlayers { player.rate = 0 }
    }

    private func itemClampedTime(_ seconds: Double, for player: AVPlayer) -> Double {
        let itemDuration = player.currentItem?.duration.seconds ?? duration
        let limit = itemDuration.isFinite ? itemDuration : duration
        return min(max(0, seconds), max(limit, 0))
    }

    func scrub(to seconds: Double) {
        guard isReady else { return }
        isScrubbing = true
        let clamped = clampedTime(seconds)
        currentTime = clamped
        for player in allPlayers {
            player.seek(
                to: CMTime(seconds: itemClampedTime(clamped, for: player), preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
        }
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        seek(to: currentTime)
    }

    func seek(to seconds: Double) {
        guard isReady else { return }
        let clamped = clampedTime(seconds)
        currentTime = clamped
        seekAll(to: clamped, precise: true)
    }

    private func seekAll(to seconds: Double, precise: Bool) {
        for player in allPlayers {
            let t = CMTime(seconds: itemClampedTime(seconds, for: player), preferredTimescale: 600)
            if precise {
                player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                player.seek(to: t)
            }
        }
    }

    private func seekAllPrecisely(to seconds: Double) async {
        await withTaskGroup(of: Void.self) { group in
            for player in allPlayers {
                let t = CMTime(seconds: itemClampedTime(seconds, for: player), preferredTimescale: 600)
                group.addTask { @MainActor in
                    await withCheckedContinuation { continuation in
                        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    func step(byFrames frameCount: Int) {
        let frameDuration = playback?.frameDuration
        let frameSeconds = frameDuration?.seconds.isFinite == true && (frameDuration?.seconds ?? 0) > 0
            ? frameDuration?.seconds ?? 1.0 / 30.0
            : 1.0 / 30.0
        seek(by: Double(frameCount) * frameSeconds)
    }

    func setHidden(_ hidden: Bool, kind: SceneLayerKind) {
        guard playback != nil else { return }
        if hidden { hiddenKinds.insert(kind) } else { hiddenKinds.remove(kind) }
        applyPreviewDuration()
    }

    func setMuted(_ muted: Bool, source: CaptureSource) {
        guard playback != nil else { return }
        if muted { mutedSources.insert(source) } else { mutedSources.remove(source) }
        audioPlayer?.currentItem?.audioMix = audioMix()
    }

    func applyEditorState(_ state: RecordingProject.EditorStateSnapshot) {
        hiddenKinds = Set(state.hiddenVideoSources.compactMap(SceneLayerKind.init(rawValue:)))
        mutedSources = Set(state.mutedAudioSources.compactMap(CaptureSource.init(rawValue:)))
        hiddenKinds.formIntersection(hideableKinds)
        mutedSources.formIntersection(muteableSources)
        applyPreviewDuration()
        audioPlayer?.currentItem?.audioMix = audioMix()
    }

    func setPreviewSceneOverride(_ scene: RecordingScene?, at seconds: Double) {
        guard playback != nil else { return }
        previewSceneOverride = scene.map { ($0, clampedTime(seconds)) }
        previewSceneRevision &+= 1
    }

    func layerFrames(at seconds: Double) -> [(kind: SceneLayerKind, frame: CGRect)] {
        guard let playback, renderSize.width > 0, renderSize.height > 0 else { return [] }
        let time = CMTime(seconds: clampedTime(seconds), preferredTimescale: 600)
        let renderSegments = playback.renderSegments(hiding: hiddenKinds)
        let segment = renderSegments.first {
            CMTimeRangeContainsTime($0.timeRange, time: time)
        } ?? renderSegments.last
        guard let segment else { return [] }
        return playback.normalizedLayerFrames(
            scene: segment.scene,
            activeLayerOrder: segment.activeLayerOrder,
            hiding: hiddenKinds
        )
    }

    func layerFrames(for scene: RecordingScene) -> [(kind: SceneLayerKind, frame: CGRect)] {
        guard let playback else { return [] }
        return playback.normalizedLayerFrames(scene: scene, hiding: hiddenKinds)
    }

    func pauseForEditing() {
        guard isReady else { return }
        pauseAll()
        isPlaying = false
        if let seconds = masterPlayer?.currentTime().seconds, seconds.isFinite {
            currentTime = clampedTime(seconds)
        }
    }

    func displayTime() -> Double {
        guard isReady, isPlaying, !isScrubbing else { return currentTime }
        guard let seconds = masterPlayer?.currentTime().seconds, seconds.isFinite else { return currentTime }
        return clampedTime(seconds)
    }

    func teardown() {
        loadGeneration += 1
        teardownPlayers()
        isPlaying = false
        isReady = false
        loadedProjectPath = nil
        loadedMediaSignature = nil
        previewSceneOverride = nil
        previewSceneRevision &+= 1
    }

    private func teardownPlayers() {
        if let timeObserver, let masterPlayer {
            masterPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        for player in allPlayers {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        videoPlayers = [:]
        audioPlayer = nil
        playbackClockPlayer = nil
        audioComposition = nil
        audioMixTracks = []
    }

    private func applyPreviewDuration() {
        guard let playback else { return }
        let previewDuration = playback.duration(hiding: hiddenKinds)
        duration = max(0, previewDuration.seconds)
        if currentTime > duration { seek(to: duration) }
    }

    private func clampedTime(_ seconds: Double) -> Double {
        min(max(0, seconds), max(duration, 0))
    }

    private func installObservers() {
        guard let masterPlayer else { return }
        timeObserver = masterPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                let seconds = time.seconds.isFinite ? time.seconds : 0
                self.currentTime = self.clampedTime(seconds)
                self.isPlaying = (self.masterPlayer?.rate ?? 0) != 0
            }
        }
        if let masterItem = masterPlayer.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: masterItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pauseAll()
                    self.isPlaying = false
                    self.currentTime = self.duration
                }
            }
        }
    }

}
