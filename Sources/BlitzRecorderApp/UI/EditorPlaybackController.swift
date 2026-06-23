import AVFoundation
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class EditorPlaybackController {
    let player = AVPlayer()

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
    }

    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var isReady = false
    private(set) var loadError: String?
    private(set) var renderSize: CGSize = .zero
    private(set) var previewRevision = 0
    private(set) var hiddenKinds: Set<SceneLayerKind> = []
    private(set) var mutedSources: Set<CaptureSource> = []

    @ObservationIgnored private var playback: EditorPlaybackComposition?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loadedProjectPath: String?
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var previewSceneOverride: (scene: RecordingScene, time: Double)?

    var hideableKinds: Set<SceneLayerKind> {
        Set(playback?.videoKinds ?? [])
    }

    var muteableSources: Set<CaptureSource> {
        Set(playback?.audioInputs.map(\.source) ?? [])
    }

    func load(project: RecordingProject, baseSettings: RecordingSettings) async {
        loadGeneration += 1
        let generation = loadGeneration

        let isSameProject = loadedProjectPath == project.projectPath
        let resumeTime = isSameProject ? currentTime : 0
        let wasPlaying = isSameProject && isPlaying

        player.pause()
        isPlaying = false
        isReady = false
        loadError = nil

        let store = TakeFileStore()
        let outputFormat = OutputVideoFormat(rawValue: project.settings.outputVideoFormat)
            ?? baseSettings.outputVideoFormat
        let settings = store.recordingSettings(
            from: project,
            baseSettings: baseSettings,
            outputFormat: outputFormat
        )
        let take = store.recordingTake(from: project, settings: settings, outputFormat: outputFormat)
        let sceneEvents = store.sceneEvents(from: project)

        do {
            let playback = try await Merger.editorPlaybackComposition(
                take: take,
                settings: settings,
                sceneEvents: sceneEvents
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            self.playback = playback
            loadedProjectPath = project.projectPath
            renderSize = playback.renderSize
            previewSceneOverride = nil
            if isSameProject {
                hiddenKinds.formIntersection(Set(playback.videoKinds))
                mutedSources.formIntersection(Set(playback.audioInputs.map(\.source)))
            } else {
                hiddenKinds = []
                mutedSources = []
            }

            let item = playback.playerItem(
                hiding: hiddenKinds,
                muting: mutedSources
            )
            item.preferredForwardBufferDuration = 0.1
            player.replaceCurrentItem(with: item)
            applyPreviewDuration(playback)
            installTimeObserverIfNeeded()

            if resumeTime > 0 {
                currentTime = min(resumeTime, duration)
                await seekPlayerPrecisely(to: currentTime)
            } else {
                currentTime = 0
                await seekPlayerPrecisely(to: 0)
            }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            isReady = true
            if wasPlaying {
                player.play()
                isPlaying = true
            }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            playback = nil
            loadedProjectPath = nil
            duration = 0
            renderSize = .zero
            loadError = error.localizedDescription
        }
    }

    func togglePlayback() {
        guard isReady, player.currentItem != nil else { return }
        if player.rate != 0 {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.05 {
                player.seek(to: .zero)
                currentTime = 0
            }
            player.play()
        }
        isPlaying = player.rate != 0
    }

    func scrub(to seconds: Double) {
        guard isReady else { return }
        isScrubbing = true
        let clamped = clampedTime(seconds)
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)
        )
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
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
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
        guard let playback else { return }
        if hidden {
            hiddenKinds.insert(kind)
        } else {
            hiddenKinds.remove(kind)
        }
        applyVideoComposition(playback)
        applyPreviewDuration(playback)
    }

    func setMuted(_ muted: Bool, source: CaptureSource) {
        guard let playback else { return }
        if muted {
            mutedSources.insert(source)
        } else {
            mutedSources.remove(source)
        }
        player.currentItem?.audioMix = playback.audioMix(muting: mutedSources)
    }

    func setPreviewSceneOverride(_ scene: RecordingScene?, at seconds: Double) {
        guard let playback else { return }
        previewSceneOverride = scene.map { ($0, clampedTime(seconds)) }
        applyVideoComposition(playback)
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
        player.pause()
        isPlaying = false
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            currentTime = clampedTime(seconds)
        }
    }

    func displayTime() -> Double {
        guard isReady, player.rate != 0, !isScrubbing else { return currentTime }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return currentTime }
        return clampedTime(seconds)
    }

    func teardown() {
        loadGeneration += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        isReady = false
        loadedProjectPath = nil
        previewSceneOverride = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func applyVideoComposition(_ playback: EditorPlaybackComposition) {
        guard let item = player.currentItem else { return }
        if let previewSceneOverride {
            item.videoComposition = playback.videoComposition(
                hiding: hiddenKinds,
                overriding: previewSceneOverride.scene,
                at: CMTime(seconds: previewSceneOverride.time, preferredTimescale: 600)
            )
        } else {
            item.videoComposition = playback.videoComposition(hiding: hiddenKinds)
        }
        previewRevision += 1

        guard isReady, player.rate == 0 else { return }
        let time = CMTime(seconds: clampedTime(currentTime), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func applyPreviewDuration(_ playback: EditorPlaybackComposition) {
        let previewDuration = playback.duration(hiding: hiddenKinds)
        duration = max(0, previewDuration.seconds)
        player.currentItem?.forwardPlaybackEndTime = previewDuration
        if currentTime > duration {
            seek(to: duration)
        }
    }

    private func clampedTime(_ seconds: Double) -> Double {
        min(max(0, seconds), max(duration, 0))
    }

    private func seekPlayerPrecisely(to seconds: Double) async {
        guard player.currentItem != nil else { return }
        let time = CMTime(seconds: clampedTime(seconds), preferredTimescale: 600)
        await withCheckedContinuation { continuation in
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                self.isPlaying = self.player.rate != 0
            }
        }
    }
}
