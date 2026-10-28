import AVFoundation
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorPlaybackController: NowPlayingPlayback {
    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false {
        didSet {
            if oldValue != isPlaying { NowPlayingController.shared.refresh() }
        }
    }
    private(set) var isReady = false
    private(set) var bypassesVoiceCleanup = false
    private(set) var loadError: String?
    private(set) var renderSize: CGSize = .zero
    private(set) var hiddenKinds: Set<SceneLayerKind> = [] {
        didSet {
            if oldValue != hiddenKinds { invalidateRenderSegments() }
        }
    }
    private(set) var mutedSources: Set<CaptureSource> = []
    private(set) var audioLevels = EditorAudioLevels.unity
    private(set) var previewSceneRevision = 0
    private(set) var playbackRate = EditorPlaybackRate.normal
    private(set) var playbackVolume: Double = 1
    private(set) var edits = TimelineEdits.empty {
        didSet {
            if oldValue.captions != edits.captions || oldValue.cuts != edits.cuts {
                captionTimeline = CaptionTimeline(.init(track: edits.captions, cuts: edits.cuts))
            }
        }
    }
    private(set) var captionTimeline = CaptionTimeline.empty
    private(set) var privacyMaskPreview: PrivacyMask?

    func setPrivacyMaskPreview(_ mask: PrivacyMask?) {
        privacyMaskPreview = mask
        previewSceneRevision &+= 1
    }

    func finishPrivacyMaskPreview(_ masks: [PrivacyMask]) {
        edits.privacyMasks = masks
        setPrivacyMaskPreview(nil)
    }
    struct TextFramePreview {
        let id: EditorPlacedItem.ID
        let frame: CGRect
    }

    func previewTextFrame(_ preview: TextFramePreview) {
        if preview.id.kind == .text, let index = edits.textOverlays.firstIndex(where: { $0.id == preview.id.value }) {
            edits.textOverlays[index].frame = preview.frame
        } else if preview.id.kind == .caption {
            edits.captions.frame = preview.frame
        }
        previewSceneRevision &+= 1
    }

    func restoreTextPreview(_ source: TimelineEdits) {
        edits.textOverlays = source.textOverlays
        edits.captions = source.captions
        previewSceneRevision &+= 1
    }

    private(set) var cursorTrack = CursorPresentationTrack.empty
    var timeMap: TimelineTimeMap {
        exportedTimeMap ?? playback?.timeMap ?? .identity(takeDuration: MediaTime.zero)
    }

    @ObservationIgnored private var playback: EditorPlaybackComposition? {
        didSet {
            invalidateRenderSegments()
            compositionRevision &+= 1
        }
    }
    /// The composition itself is not observed; views that read values derived from it depend on this instead.
    private var compositionRevision = 0
    @ObservationIgnored private var cachedRenderSegments: [FinalExportRenderSegment]?
    @ObservationIgnored private var cachedPreviewRenderSegments: [FinalExportRenderSegment]?
    @ObservationIgnored private var cachedLayerFrames: (
        range: CMTimeRange,
        hiding: Set<SceneLayerKind>,
        revision: Int,
        frames: [(kind: SceneLayerKind, frame: CGRect)]
    )?
    @ObservationIgnored private var cachedSceneAt: (
        range: CMTimeRange,
        revision: Int,
        scene: RecordingScene
    )?
    @ObservationIgnored private var videoPlayers: [SceneLayerKind: AVPlayer] = [:]
    @ObservationIgnored private var cameraAnglePlayers: [String: AVPlayer] = [:]
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var exportedPlayer: AVPlayer?
    @ObservationIgnored private var exportedTimeMap: TimelineTimeMap?
    @ObservationIgnored private var audioMixTracks: [AudioMixTrack] = []
    @ObservationIgnored private var audioComposition: AVMutableComposition?
    @ObservationIgnored private var playbackClockPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var nowPlayingTitle = "Recording"
    @ObservationIgnored private var loadedProjectPath: String?
    @ObservationIgnored private var loadedMediaSignature: EditorPlaybackMediaSignature?
    /// What the audio player was built with. Video players do not depend on it.
    @ObservationIgnored private var loadedVoiceCleanup: VoiceCleanupSettings?
    /// Bumped on every audio request so an older, slower one never installs over a newer choice.
    @ObservationIgnored private var audioRequestID = 0
    /// The latest cleanup asked for, so a repeat of an in-flight request is not started twice.
    @ObservationIgnored private var requestedVoiceCleanup: VoiceCleanupSettings?
    /// Kept across a swap that a newer one replaces, so playback still resumes when the last one lands.
    @ObservationIgnored private var resumesAfterAudioSwap = false
    /// True while the audio player is being replaced; play requests wait for it instead of failing.
    @ObservationIgnored private var isSwappingAudio = false
    /// Keeps the tracks of a voice cleanup swap alive; the main composition owns the first load's tracks.
    @ObservationIgnored private var rebuiltAudioSource: AVComposition?
    @ObservationIgnored private var activeAudioReloads = 0
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var resumesAfterScrub = false
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private var lastAudiblePlaybackVolume: Double = 1
    @ObservationIgnored private var readinessContinuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var loadGeneration = 0 {
        didSet {
            readinessContinuation?.finish()
            readinessContinuation = nil
        }
    }
    @ObservationIgnored private var previewSceneOverride: (scene: RecordingScene, time: Double)? {
        didSet { cachedPreviewRenderSegments = nil }
    }

    var hideableKinds: Set<SceneLayerKind> {
        _ = compositionRevision
        return Set(playback?.videoKinds ?? [])
    }

    var muteableSources: Set<CaptureSource> {
        _ = compositionRevision
        return Set(playback?.audioInputs.map(\.source) ?? [])
    }

    /// The project recorded a Camera 2, so two-camera layouts can show it.
    var hasSecondCamera: Bool {
        _ = compositionRevision
        return playback?.videoKinds.contains(.secondCamera) == true
    }

    var sourceAspectRatios: [SceneLayerKind: CGFloat] {
        playback?.sourceAspectRatios ?? [:]
    }

    /// The player for a layer in a scene: the camera layer plays the scene's camera angle when it was recorded.
    func videoPlayer(for kind: SceneLayerKind, scene: RecordingScene) -> AVPlayer? {
        let feed = scene.feed(for: kind, available: Set(cameraAnglePlayers.keys).union([kind.defaultFeed]))
        return cameraAnglePlayers[feed] ?? videoPlayers[kind]
    }

    /// Source aspect ratios as a scene shows them, with the camera angle's own ratio in the camera layer.
    func sourceAspectRatios(for scene: RecordingScene) -> [SceneLayerKind: CGFloat] {
        var ratios = sourceAspectRatios
        let mainCameraRatio = ratios[.camera]
        if let angleRatio = playback?.cameraAngleAspectRatios[scene.cameraFeeds.camera] {
            ratios[.camera] = angleRatio
        }
        if scene.sceneLayout.secondCameraFrame != nil {
            ratios[.secondCamera] = playback?.cameraAngleAspectRatios[scene.cameraFeeds.secondCamera] ?? mainCameraRatio
        }
        return ratios
    }

    private var masterPlayer: AVPlayer? {
        exportedPlayer ?? playbackClockPlayer
    }

    private var allPlayers: [AVPlayer] {
        if let exportedPlayer {
            return [exportedPlayer]
        }
        var players = Array(videoPlayers.values) + Array(cameraAnglePlayers.values)
        if let audioPlayer { players.append(audioPlayer) }
        return players
    }

    var filePlayer: AVPlayer? { exportedPlayer }

    /// Both microphone versions are already in the audio player, so Before | After only changes volumes.
    func setVoiceCleanupBypassed(_ bypassed: Bool) {
        bypassesVoiceCleanup = bypassed
        refreshAudioMix()
    }

    private var inactiveMicrophoneVersion: EditorMicrophoneVersion {
        bypassesVoiceCleanup ? .cleaned : .original
    }

    /// The microphone file being heard, for the timeline waveform; nil when cleanup is off.
    var heardMicrophoneURL: URL? {
        _ = compositionRevision
        return playback?.audioInputs.first {
            $0.source == .microphone && $0.version != nil && $0.version != inactiveMicrophoneVersion
        }?.url
    }

    /// Progress of the voice cleanup being prepared, nil when nothing is processing.
    private(set) var audioProgress: Double?

    /// Cleanup only changes the microphone audio, so swap the audio player in place and keep the
    /// video, the scene and the playhead where they are.
    func reloadAudioIfNeeded(_ request: AudioReload) async {
        guard isReady, let playback, loadedProjectPath == request.project.projectPath else { return }
        let resolved = ProjectSettings(project: request.project, baseSettings: request.baseSettings)
        let cleanup = Self.playbackVoiceCleanup(resolved.settings.voiceCleanup)
        guard cleanup != (requestedVoiceCleanup ?? loadedVoiceCleanup) else { return }
        audioRequestID &+= 1
        let requestID = audioRequestID
        requestedVoiceCleanup = cleanup
        let generation = loadGeneration
        // The refresh that asked may be cancelled by the next edit; a repeat of this request then waits on
        // this one, so it has to finish on its own.
        await Task { @MainActor in
            await self.performAudioReload(.init(
                request: request, settings: resolved.settings, outputFormat: resolved.outputFormat, timeMap: playback.timeMap,
                cleanup: cleanup, requestID: requestID, generation: generation))
        }.value
    }

    private func performAudioReload(_ work: AudioReloadWork) async {
        let request = work.request
        let settings = work.settings
        let cleanup = work.cleanup
        let requestID = work.requestID
        let generation = work.generation
        let isCurrent = { generation == self.loadGeneration && requestID == self.audioRequestID }
        activeAudioReloads += 1
        audioProgress = 0
        defer {
            activeAudioReloads -= 1
            if activeAudioReloads == 0 { audioProgress = nil }
        }
        let audio: Merger.EditorPlaybackAudio
        do {
            audio = try await Merger.editorPlaybackAudio(.init(
                take: TakeFileStore().recordingTake(from: request.project, settings: settings, outputFormat: work.outputFormat),
                settings: settings,
                timeMap: work.timeMap,
                progress: { [weak self] value in
                    Task { @MainActor in
                        guard let self, requestID == self.audioRequestID else { return }
                        self.audioProgress = value
                    }
                }
            ))
        } catch {
            if requestID == audioRequestID { requestedVoiceCleanup = nil }
            guard isCurrent(), !(error is CancellationError) else { return }
            await load(project: request.project, baseSettings: request.baseSettings)
            return
        }
        guard isCurrent(), isReady else {
            if requestID == audioRequestID { requestedVoiceCleanup = nil }
            return
        }
        await installAudio(.init(audio: audio, cleanup: cleanup, requestID: requestID, generation: generation))
    }

    private func installAudio(_ install: AudioInstall) async {
        let isCurrent = { install.generation == self.loadGeneration && install.requestID == self.audioRequestID }
        guard isCurrent(), var updated = playback else { return }
        let time = currentTime
        resumesAfterAudioSwap = resumesAfterAudioSwap || isPlaying
        isSwappingAudio = true
        defer { isSwappingAudio = false }
        pausePlayback()
        removeClockObservers()
        audioPlayer?.pause()
        audioPlayer?.replaceCurrentItem(with: nil)
        audioPlayer = nil
        audioComposition = nil
        audioMixTracks = []
        updated.audioInputs = install.audio.inputs
        playback = updated
        rebuiltAudioSource = install.audio.composition
        buildAudioPlayer(playback: updated)
        if let audioPlayer {
            _ = try? await waitForPlayersReady((players: [audioPlayer], generation: install.generation))
        }
        guard isCurrent() else { return }
        let clockPlayer = await Self.longestPlayer(among: clockCandidates)
        guard isCurrent() else { return }
        playbackClockPlayer = clockPlayer
        installObservers()
        await seekAllPrecisely(to: time)
        guard isCurrent() else { return }
        loadedVoiceCleanup = install.cleanup
        requestedVoiceCleanup = nil
        isSwappingAudio = false
        if resumesAfterAudioSwap { isPlaying = playAll() }
        resumesAfterAudioSwap = false
    }

    func loadExported(url: URL, title: String) async {
        loadGeneration += 1
        let generation = loadGeneration
        pausePlayback()
        isReady = false
        loadError = nil
        teardownPlayers()
        playback = nil
        edits = .empty
        hiddenKinds = []
        mutedSources = []
        audioLevels = .unity
        loadedProjectPath = nil
        loadedMediaSignature = nil
        previewSceneOverride = nil

        do {
            let asset = AVURLAsset(url: url)
            let info = try await Self.exportedAssetInfo(asset)
            guard isCurrentLoad(generation) else { return }
            let player = Self.makePlayer(AVPlayerItem(asset: asset))
            exportedPlayer = player
            guard try await waitForPlayersReady((players: [player], generation: generation)) else { return }
            guard isCurrentLoad(generation) else { return }
            playbackClockPlayer = player
            nowPlayingTitle = title
            self.duration = info.duration.seconds.isFinite ? max(0, info.duration.seconds) : 0
            exportedTimeMap = .identity(takeDuration: MediaTime(seconds: self.duration))
            renderSize = info.size
            previewSceneRevision &+= 1
            currentTime = 0
            installObservers()
            await seekAllPrecisely(to: 0)
            guard isCurrentLoad(generation) else { return }
            isReady = true
        } catch {
            guard isCurrentLoad(generation) else { return }
            failLoad(error)
        }
    }

    func load(project: RecordingProject, baseSettings: RecordingSettings) async {
        await load(.init(project: project, baseSettings: baseSettings, previewCuts: nil))
    }

    func load(_ request: EditorPlaybackLoadRequest) async {
        let project = request.project
        let baseSettings = request.baseSettings
        loadGeneration += 1
        let generation = loadGeneration

        let isSameProject = loadedProjectPath == project.projectPath
        if !isSameProject { bypassesVoiceCleanup = false }
        let resumeTime = isSameProject ? currentTime : 0
        let wasPlaying = isSameProject && isPlaying

        pausePlayback()
        isReady = false
        loadError = nil

        let store = TakeFileStore()
        let resolved = ProjectSettings(project: project, baseSettings: baseSettings)
        let settings = resolved.settings
        let take = store.recordingTake(from: project, settings: settings, outputFormat: resolved.outputFormat)
        let sceneEvents = store.sceneEvents(from: project)

        do {
            async let loadedCursor = CursorPresentationLoader.shared.load(.init(
                directory: URL(fileURLWithPath: project.takeDirectoryPath),
                trimOffset: project.timelineTrimOffsetSeconds))
            let playback = try await Merger.editorPlaybackComposition(
                take: take,
                settings: settings,
                sceneEvents: sceneEvents,
                cuts: request.previewCuts ?? project.edits.enabledCuts
            )
            let cursor = await loadedCursor
            guard isCurrentLoad(generation) else { return }
            teardownPlayers()
            self.playback = playback
            edits = project.edits
            cursorTrack = cursor
            loadedProjectPath = project.projectPath
            nowPlayingTitle = project.title
            loadedMediaSignature = request.previewCuts == nil ? EditorPlaybackMediaSignature(project: project) : nil
            loadedVoiceCleanup = Self.playbackVoiceCleanup(settings.voiceCleanup)
            requestedVoiceCleanup = nil
            resumesAfterAudioSwap = false
            audioRequestID &+= 1
            renderSize = playback.renderSize
            previewSceneOverride = nil
            previewSceneRevision &+= 1
            applyEditorState(project.editorState)

            buildPlayers(playback: playback)
            guard try await waitForPlayersReady((players: allPlayers, generation: generation)) else { return }
            let clockPlayer = await Self.longestPlayer(among: clockCandidates)
            guard isCurrentLoad(generation) else { return }
            playbackClockPlayer = clockPlayer
            duration = max(0, playback.timeMap.takeDuration.seconds)
            installObservers()

            let startTime = resumeTime > 0 ? min(resumeTime, duration) : 0
            currentTime = startTime
            await seekAllPrecisely(to: startTime)

            guard isCurrentLoad(generation) else { return }
            isReady = true
            if wasPlaying { isPlaying = playAll() }
        } catch {
            guard isCurrentLoad(generation) else { return }
            failLoad(error)
            playback = nil
            loadedProjectPath = nil
            loadedMediaSignature = nil
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

        guard let refreshedPlayback = try? playback.updatingSceneTimeline(EditorPlaybackSceneTimeline(
            settings: ProjectSettings(project: update.project, baseSettings: update.baseSettings).settings,
            sceneEvents: TakeFileStore().sceneEvents(from: update.project)
        )) else {
            return false
        }

        self.playback = refreshedPlayback
        nowPlayingTitle = update.project.title
        NowPlayingController.shared.updateTitle(.init(playback: self, title: nowPlayingTitle))
        edits = update.project.edits
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
            let player = Self.makePlayer(AVPlayerItem(asset: asset))
            player.isMuted = true
            videoPlayers[kind] = player
        }
        for (feed, asset) in playback.cameraAngleAssets {
            let player = Self.makePlayer(AVPlayerItem(asset: asset))
            player.isMuted = true
            cameraAnglePlayers[feed] = player
        }
        buildAudioPlayer(playback: playback)
    }

    private func buildAudioPlayer(playback: EditorPlaybackComposition) {
        guard let audio = Self.audioComposition(for: playback.audioInputs) else { return }
        audioComposition = audio.composition
        audioMixTracks = audio.tracks
        let item = AVPlayerItem(asset: audio.composition)
        item.audioMix = audioMix()
        let player = Self.makePlayer(item)
        player.volume = Float(playbackVolume)
        audioPlayer = player
    }

    private func waitForPlayersReady(_ request: (players: [AVPlayer], generation: Int)) async throws -> Bool {
        guard request.generation == loadGeneration else { return false }
        try Task.checkCancellation()
        guard !request.players.isEmpty else { throw RecorderError.playbackNotReady }
        let (updates, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        readinessContinuation = continuation
        let observations = request.players.map { player in
            player.observe(\.status, options: [.initial, .new]) { _, _ in continuation.yield(()) }
        }
        let timeout = Task {
            do {
                try await Task.sleep(for: .seconds(10))
                continuation.finish()
            } catch {}
        }
        defer {
            observations.forEach { $0.invalidate() }
            timeout.cancel()
            continuation.finish()
            if request.generation == loadGeneration { readinessContinuation = nil }
        }
        for await _ in updates {
            guard request.generation == loadGeneration else { return false }
            try Task.checkCancellation()
            if let failed = request.players.first(where: { $0.status == .failed }) {
                throw failed.error ?? RecorderError.playbackNotReady
            }
            if request.players.allSatisfy({ $0.status == .readyToPlay }) { return true }
        }
        guard request.generation == loadGeneration else { return false }
        try Task.checkCancellation()
        throw RecorderError.playbackNotReady
    }

    private var clockCandidates: [AVPlayer] {
        [audioPlayer, videoPlayers[.screen], videoPlayers[.camera]].compactMap { $0 }
    }

    private func refreshAudioMix() {
        audioPlayer?.currentItem?.audioMix = audioMix()
    }

    private func audioMix() -> AVAudioMix? {
        guard !audioMixTracks.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioMixTracks.map { entry in
            let params = AVMutableAudioMixInputParameters(track: entry.track)
            let silenced = mutedSources.contains(entry.source) || entry.version == inactiveMicrophoneVersion
            EditorAudioVolumeAutomation.apply(.init(parameters: params, source: entry.source,
                baseVolume: silenced ? 0 : entry.baseVolume * Float(audioLevels.volume(for: entry.source)),
                regions: audioLevels.regions, timeMap: timeMap))
            return params
        }
        return mix
    }

    private func invalidateRenderSegments() {
        cachedRenderSegments = nil
        cachedPreviewRenderSegments = nil
        cachedLayerFrames = nil
        cachedSceneAt = nil
    }

    private var renderSegments: [FinalExportRenderSegment] {
        if let cachedRenderSegments { return cachedRenderSegments }
        let segments = playback?.renderSegments(hiding: hiddenKinds) ?? []
        cachedRenderSegments = segments
        return segments
    }

    private var previewRenderSegments: [FinalExportRenderSegment] {
        guard let previewSceneOverride else { return renderSegments }
        if let cachedPreviewRenderSegments { return cachedPreviewRenderSegments }
        let segments = EditorPlaybackComposition.renderSegments(
            renderSegments,
            overriding: previewSceneOverride.scene,
            at: timeMap.outputTime(forTake: TimelineTimeMap.time(previewSceneOverride.time))
        )
        cachedPreviewRenderSegments = segments
        return segments
    }

    func scene(at seconds: Double) -> RecordingScene? {
        guard playback != nil else { return nil }
        let segmentScene: RecordingScene
        if isCachedSceneSegment(at: seconds), let cachedSceneAt {
            segmentScene = cachedSceneAt.scene
        } else {
            let time = outputTime(forTakeSeconds: seconds)
            let segments = previewRenderSegments
            guard let index = EditorTimelineIndex.segmentIndex(at: time, in: segments) else { return nil }
            segmentScene = segments[index].scene
            cachedSceneAt = (
                range: segments[index].timeRange,
                revision: previewSceneRevision,
                scene: segmentScene
            )
        }
        guard edits.zoom.isActive else { return segmentScene }
        return TimelineOverlayRenderer.scene(.init(scene: segmentScene, edits: edits, time: seconds))
    }

    func togglePlayback() {
        guard isReady, masterPlayer != nil else { return }
        seekGeneration += 1
        isScrubbing = false
        resumesAfterScrub = false
        if isPlaying {
            pausePlayback()
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
        seekGeneration += 1
        isScrubbing = false
        resumesAfterScrub = false
        isPlaying = playAll()
    }

    func setPlaybackRate(_ rate: EditorPlaybackRate) {
        guard playbackRate != rate else { return }
        playbackRate = rate
        guard isPlaying else { return }
        syncCurrentTimeFromMasterPlayer()
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
        if isSwappingAudio {
            resumesAfterAudioSwap = true
            return false
        }
        let players = allPlayers
        guard !players.isEmpty, players.allSatisfy({ $0.status == .readyToPlay }) else {
            pauseAll()
            isReady = false
            loadError = RecorderError.playbackNotReady.localizedDescription
            return false
        }
        NowPlayingController.shared.activate(.init(playback: self, title: nowPlayingTitle))
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let hostTime = CMTimeAdd(now, CMTime(seconds: 0.06, preferredTimescale: 600))
        for player in players {
            player.setRate(playbackRate.rawValue, time: itemTime(currentTime, for: player), atHostTime: hostTime)
        }
        return true
    }

    private func pauseAll() {
        for player in allPlayers { player.rate = 0 }
    }

    private func pausePlayback() {
        pauseAll()
        isPlaying = false
    }

    private func itemTime(_ seconds: Double, for player: AVPlayer) -> CMTime {
        let itemDuration = player.currentItem?.duration.seconds ?? duration
        let limit = itemDuration.isFinite ? itemDuration : duration
        let clamped = min(timeMap.outputSeconds(forTakeSeconds: max(0, seconds)), max(limit, 0))
        return CMTime(seconds: clamped, preferredTimescale: 600)
    }

    func scrub(to seconds: Double) {
        guard isReady else { return }
        if !isScrubbing, isPlaying {
            pauseAll()
            resumesAfterScrub = true
        }
        seekGeneration += 1
        isScrubbing = true
        let clamped = clampedTime(seconds)
        currentTime = clamped
        for player in allPlayers {
            player.seek(
                to: itemTime(clamped, for: player),
                toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)
            )
        }
    }

    func endScrub() {
        guard isScrubbing else { return }
        settle(at: currentTime)
    }

    func seek(to seconds: Double) {
        guard isReady else { return }
        if isPlaying, !isScrubbing {
            pauseAll()
            resumesAfterScrub = true
        }
        isScrubbing = true
        settle(at: seconds)
    }

    private func settle(at seconds: Double) {
        let clamped = clampedTime(seconds)
        currentTime = clamped
        seekGeneration += 1
        let generation = seekGeneration
        let load = loadGeneration
        Task { @MainActor [weak self] in
            await self?.seekAllPrecisely(to: clamped)
            guard let self, self.seekGeneration == generation, self.loadGeneration == load else { return }
            self.isScrubbing = false
            if self.resumesAfterScrub {
                self.resumesAfterScrub = false
                self.isPlaying = self.playAll()
            }
        }
    }

    private func seekAll(to seconds: Double, precise: Bool) {
        for player in allPlayers {
            let t = itemTime(seconds, for: player)
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
                let t = itemTime(seconds, for: player)
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
        let seconds = playback?.frameDuration.seconds ?? 0
        let frameSeconds = seconds.isFinite && seconds > 0 ? seconds : 1.0 / 30.0
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
        refreshAudioMix()
    }

    func setPlaybackVolume(_ volume: Double) {
        guard volume.isFinite else { return }
        playbackVolume = min(1, max(0, volume))
        if playbackVolume > 0 {
            lastAudiblePlaybackVolume = playbackVolume
        }
        audioPlayer?.volume = Float(playbackVolume)
    }

    func setTrackVolume(_ change: EditorTrackVolumeChange) {
        guard muteableSources.contains(change.source) else { return }
        audioLevels.setVolume(change)
        refreshAudioMix()
    }

    func setAudioRegionVolume(_ region: EditorAudioVolumeRegion) {
        audioLevels.setRegion(region)
        refreshAudioMix()
    }

    func restoreAudioLevels(_ levels: EditorAudioLevels) {
        audioLevels = levels
        refreshAudioMix()
    }

    func togglePlaybackMute() {
        setPlaybackVolume(playbackVolume > 0 ? 0 : lastAudiblePlaybackVolume)
    }

    func applyEditorState(_ state: RecordingProject.EditorStateSnapshot) {
        hiddenKinds = Set(state.hiddenVideoSources.compactMap(SceneLayerKind.init(rawValue:)))
        mutedSources = Set(state.mutedAudioSources.compactMap(CaptureSource.init(rawValue:)))
        audioLevels = state.audioLevels ?? .unity
        hiddenKinds.formIntersection(hideableKinds)
        mutedSources.formIntersection(muteableSources)
        applyPreviewDuration()
        refreshAudioMix()
    }

    func setPreviewSceneOverride(_ scene: RecordingScene?, at seconds: Double) {
        guard playback != nil else { return }
        previewSceneOverride = scene.map { ($0, clampedTime(seconds)) }
        previewSceneRevision &+= 1
    }

    func layerFrames(at seconds: Double) -> [(kind: SceneLayerKind, frame: CGRect)] {
        guard let playback, renderSize.width > 0, renderSize.height > 0 else { return [] }
        let time = outputTime(forTakeSeconds: seconds)
        if let cachedLayerFrames,
           cachedLayerFrames.hiding == hiddenKinds,
           cachedLayerFrames.revision == previewSceneRevision,
           CMTimeRangeContainsTime(cachedLayerFrames.range, time: time) {
            return cachedLayerFrames.frames
        }
        let renderSegments = self.renderSegments
        guard let index = EditorTimelineIndex.segmentIndex(at: time, in: renderSegments) else { return [] }
        let segment = renderSegments[index]
        let frames = playback.normalizedLayerFrames(
            scene: segment.scene,
            activeLayerOrder: segment.activeLayerOrder,
            hiding: hiddenKinds
        )
        cachedLayerFrames = (
            range: segment.timeRange,
            hiding: hiddenKinds,
            revision: previewSceneRevision,
            frames: frames
        )
        return frames
    }

    func layerFrames(for scene: RecordingScene) -> [(kind: SceneLayerKind, frame: CGRect)] {
        guard let playback else { return [] }
        return playback.normalizedLayerFrames(scene: scene, hiding: hiddenKinds)
    }

    func pauseForEditing() {
        guard isReady else { return }
        pausePlayback()
        syncCurrentTimeFromMasterPlayer()
    }

    func displayTime() -> Double {
        guard isReady, isPlaying, !isScrubbing else { return currentTime }
        guard let seconds = masterPlayer?.currentTime().seconds, seconds.isFinite else { return currentTime }
        return clampedTime(timeMap.takeSeconds(forOutputSeconds: seconds))
    }

    func teardown() {
        cursorTrack = .empty
        NowPlayingController.shared.deactivate(self)
        loadGeneration += 1
        teardownPlayers()
        isPlaying = false
        isReady = false
        loadedProjectPath = nil
        loadedMediaSignature = nil
        invalidateRenderSegments()
        previewSceneOverride = nil
        previewSceneRevision &+= 1
    }

    private func removeClockObservers() {
        if let timeObserver, let masterPlayer {
            masterPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func teardownPlayers() {
        removeClockObservers()
        for player in allPlayers {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        videoPlayers = [:]
        cameraAnglePlayers = [:]
        audioPlayer = nil
        exportedPlayer = nil
        exportedTimeMap = nil
        playbackClockPlayer = nil
        audioComposition = nil
        audioMixTracks = []
        rebuiltAudioSource = nil
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    private func failLoad(_ error: Error) {
        teardownPlayers()
        duration = 0
        renderSize = .zero
        loadError = error.localizedDescription
    }

    private func applyPreviewDuration() {
        guard let playback else { return }
        duration = max(0, playback.timeMap.takeDuration.seconds)
        if currentTime > duration { seek(to: duration) }
    }

    private func clampedTime(_ seconds: Double) -> Double {
        min(max(0, seconds), max(duration, 0))
    }

    private func outputTime(forTakeSeconds seconds: Double) -> CMTime {
        timeMap.outputTime(forTake: TimelineTimeMap.time(clampedTime(seconds)))
    }

    private func syncCurrentTimeFromMasterPlayer() {
        if let seconds = masterPlayer?.currentTime().seconds, seconds.isFinite {
            currentTime = clampedTime(timeMap.takeSeconds(forOutputSeconds: seconds))
        }
    }

    private func isCachedSceneSegment(at seconds: Double) -> Bool {
        guard let cachedSceneAt, cachedSceneAt.revision == previewSceneRevision else { return false }
        let time = outputTime(forTakeSeconds: seconds)
        return CMTimeRangeContainsTime(cachedSceneAt.range, time: time)
    }

    private func installObservers() {
        guard let masterPlayer else { return }
        let generation = loadGeneration
        timeObserver = masterPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.loadGeneration == generation, self.isReady, !self.isScrubbing else { return }
                let seconds = time.seconds.isFinite ? time.seconds : 0
                let nextTime = self.clampedTime(self.timeMap.takeSeconds(forOutputSeconds: seconds))
                let nextIsPlaying = (self.masterPlayer?.rate ?? 0) != 0
                let update = EditorPlaybackClockPublish.apply(.init(
                    nextTime: nextTime,
                    currentTime: self.currentTime,
                    nextIsPlaying: nextIsPlaying,
                    isPlaying: self.isPlaying,
                    isSameSceneSegment: self.isCachedSceneSegment(at: nextTime)
                ))
                if let currentTime = update.currentTime {
                    self.currentTime = currentTime
                }
                if let isPlaying = update.isPlaying {
                    self.isPlaying = isPlaying
                }
                if update.shouldRefreshSceneCache {
                    _ = self.scene(at: nextTime)
                }
            }
        }
        if let masterItem = masterPlayer.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: masterItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.loadGeneration == generation, self.isReady else { return }
                    self.pausePlayback()
                    self.currentTime = self.duration
                }
            }
        }
    }
}
