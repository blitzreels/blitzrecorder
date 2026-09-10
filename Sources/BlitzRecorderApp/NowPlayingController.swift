import AppKit
import MediaPlayer
import Observation

@MainActor
protocol NowPlayingPlayback: AnyObject {
    var isReady: Bool { get }
    var isPlaying: Bool { get }
    var playbackRate: EditorPlaybackRate { get }
    var nowPlayingDuration: Double { get }
    var nowPlayingTime: Double { get }
    func togglePlayback()
    func pauseForEditing()
    func seekFromNowPlaying(to seconds: Double)
    func setPlaybackRate(_ rate: EditorPlaybackRate)
}

@MainActor
@Observable
final class NowPlayingController: NSObject {
    static let shared = NowPlayingController()

    private(set) var title = ""
    private(set) var isPlaying = false
    private(set) var hasMedia = false
    private(set) var elapsedTime: Double = 0
    private(set) var duration: Double = 0
    @ObservationIgnored private weak var playback: (any NowPlayingPlayback)?
    @ObservationIgnored private var observationTimer: Timer?
    @ObservationIgnored private var lastInfo: Snapshot?
    private let publishesToSystem: Bool

    struct Snapshot: Equatable {
        let title: String
        let duration: Double
        let elapsed: Double
        let rate: Double
    }

    struct Registration {
        let playback: any NowPlayingPlayback
        let title: String
    }

    enum Command {
        case play
        case pause
        case toggle
        case skip(Double)
        case seek(Double)
        case rate(EditorPlaybackRate)
    }

    init(publishesToSystem: Bool = true) {
        self.publishesToSystem = publishesToSystem
        super.init()
        guard publishesToSystem else { return }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget(self, action: #selector(handlePlay))
        commands.pauseCommand.addTarget(self, action: #selector(handlePause))
        commands.togglePlayPauseCommand.addTarget(self, action: #selector(handleToggle))
        commands.skipBackwardCommand.preferredIntervals = [10]
        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.addTarget(self, action: #selector(handleSkipBackward))
        commands.skipForwardCommand.addTarget(self, action: #selector(handleSkipForward))
        commands.changePlaybackPositionCommand.addTarget(self, action: #selector(handlePosition))
        commands.changePlaybackRateCommand.supportedPlaybackRates = EditorPlaybackRate.allCases.map {
            NSNumber(value: $0.rawValue)
        }
        commands.changePlaybackRateCommand.addTarget(self, action: #selector(handleRate))
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
        setCommandsEnabled(false)
    }

    func activate(_ registration: Registration) {
        if let playback, playback !== registration.playback {
            playback.pauseForEditing()
        }
        playback = registration.playback
        title = registration.title
        refresh()
        guard publishesToSystem, observationTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func deactivate(_ owner: any NowPlayingPlayback) {
        guard playback === owner else { return }
        clear()
    }

    func suspendForRecording() {
        playback?.pauseForEditing()
        clear()
    }

    func updateTitle(_ registration: Registration) {
        guard playback === registration.playback else { return }
        title = registration.title
        refresh()
    }

    @discardableResult
    func perform(_ command: Command) -> MPRemoteCommandHandlerStatus {
        guard let playback, playback.isReady else { return .noActionableNowPlayingItem }
        switch command {
        case .play:
            if !playback.isPlaying { playback.togglePlayback() }
        case .pause:
            playback.pauseForEditing()
        case .toggle:
            playback.togglePlayback()
        case .skip(let delta):
            guard delta.isFinite else { return .commandFailed }
            playback.seekFromNowPlaying(to: min(playback.nowPlayingDuration, max(0, playback.nowPlayingTime + delta)))
        case .seek(let seconds):
            guard seconds.isFinite else { return .commandFailed }
            playback.seekFromNowPlaying(to: min(playback.nowPlayingDuration, max(0, seconds)))
        case .rate(let rate):
            playback.setPlaybackRate(rate)
        }
        refresh()
        return .success
    }

    func refresh() {
        guard let playback, playback.isReady else {
            clear()
            return
        }
        hasMedia = true
        isPlaying = playback.isPlaying
        elapsedTime = playback.nowPlayingTime
        duration = playback.nowPlayingDuration
        guard publishesToSystem else { return }
        let snapshot = Snapshot(
            title: title,
            duration: playback.nowPlayingDuration,
            elapsed: playback.nowPlayingTime,
            rate: isPlaying ? Double(playback.playbackRate.rawValue) : 0
        )
        guard snapshot != lastInfo else { return }
        lastInfo = snapshot
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: "BlitzRecorder",
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playback.playbackRate.rawValue),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]
        center.playbackState = isPlaying ? .playing : .paused
        setCommandsEnabled(true)
    }

    private func clear() {
        playback = nil
        hasMedia = false
        isPlaying = false
        title = ""
        elapsedTime = 0
        duration = 0
        observationTimer?.invalidate()
        observationTimer = nil
        lastInfo = nil
        guard publishesToSystem else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        setCommandsEnabled(false)
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
                        commands.skipBackwardCommand, commands.skipForwardCommand,
                        commands.changePlaybackPositionCommand, commands.changePlaybackRateCommand] {
            command.isEnabled = enabled
        }
    }

    nonisolated private func dispatch(_ command: Command) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { perform(command) }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { perform(command) }
        }
    }

    @objc nonisolated private func handlePlay(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        dispatch(.play)
    }

    @objc nonisolated private func handlePause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        dispatch(.pause)
    }

    @objc nonisolated private func handleToggle(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        dispatch(.toggle)
    }

    @objc nonisolated private func handleSkipBackward(_ event: MPSkipIntervalCommandEvent) -> MPRemoteCommandHandlerStatus {
        dispatch(.skip(-event.interval))
    }

    @objc nonisolated private func handleSkipForward(_ event: MPSkipIntervalCommandEvent) -> MPRemoteCommandHandlerStatus {
        dispatch(.skip(event.interval))
    }

    @objc nonisolated private func handlePosition(_ event: MPChangePlaybackPositionCommandEvent) -> MPRemoteCommandHandlerStatus {
        dispatch(.seek(event.positionTime))
    }

    @objc nonisolated private func handleRate(_ event: MPChangePlaybackRateCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let rate = EditorPlaybackRate(rawValue: event.playbackRate) else { return .commandFailed }
        return dispatch(.rate(rate))
    }
}
