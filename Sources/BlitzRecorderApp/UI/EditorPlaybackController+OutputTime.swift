import Foundation

extension EditorPlaybackController {
    var outputDuration: Double { timeMap.outputDuration.seconds }

    var nowPlayingDuration: Double { outputDuration }

    var nowPlayingTime: Double { timeMap.outputSeconds(forTakeSeconds: currentTime) }

    func playFromOutput(_ seconds: Double) {
        play(from: timeMap.takeSeconds(forOutputSeconds: seconds))
    }

    func scrubToOutput(_ seconds: Double) {
        scrub(to: timeMap.takeSeconds(forOutputSeconds: seconds))
    }

    func seekFromNowPlaying(to seconds: Double) {
        guard seconds.isFinite else { return }
        seek(to: timeMap.takeSeconds(forOutputSeconds: seconds))
    }
}
