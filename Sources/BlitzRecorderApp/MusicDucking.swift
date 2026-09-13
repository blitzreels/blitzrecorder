import AVFoundation

struct MusicDuckingRange: Equatable {
    let start: Double
    let end: Double
}

enum MusicDucking {
    struct Request {
        let windows: [SilenceWindow]
        let threshold: Double
        let timeMap: TimelineTimeMap
    }

    static func ranges(_ request: Request) -> [MusicDuckingRange] {
        var ranges: [MusicDuckingRange] = []
        for window in request.windows where window.decibels > request.threshold {
            let start = request.timeMap.outputSeconds(forTakeSeconds: window.start)
            let end = request.timeMap.outputSeconds(forTakeSeconds: window.end)
            guard end > start else { continue }
            let expanded = MusicDuckingRange(start: max(0, start - 0.1), end: min(request.timeMap.outputDuration.seconds, end + 0.3))
            if let previous = ranges.last, expanded.start <= previous.end + 0.2 {
                ranges[ranges.count - 1] = .init(start: previous.start, end: max(previous.end, expanded.end))
            } else { ranges.append(expanded) }
        }
        return ranges
    }

    struct MixRequest {
        let parameters: AVMutableAudioMixInputParameters
        let ranges: [MusicDuckingRange]
        let volume: Float
        let duration: Double
    }

    static func apply(_ request: MixRequest) {
        guard request.duration > 0 else { return }
        let fadeStart = max(0, request.duration - 0.75)
        var points: Set<Double> = [0, fadeStart, request.duration]
        for range in request.ranges {
            let attackEnd = min(range.end, range.start + 0.08)
            let releaseStart = max(attackEnd, range.end - 0.25)
            points.formUnion([range.start, attackEnd, releaseStart, range.end])
        }
        for time in stride(from: fadeStart, to: request.duration, by: 0.05) { points.insert(time) }
        let ordered = points.filter { $0 >= 0 && $0 <= request.duration }.sorted()
        func volume(at time: Double) -> Float {
            var gain = 1.0
            if let range = request.ranges.first(where: { time >= $0.start && time <= $0.end }) {
                let attackEnd = min(range.end, range.start + 0.08)
                let releaseStart = max(attackEnd, range.end - 0.25)
                if time < attackEnd {
                    gain = 1 - 0.75 * (time - range.start) / max(0.001, attackEnd - range.start)
                } else if time > releaseStart {
                    gain = 0.25 + 0.75 * (time - releaseStart) / max(0.001, range.end - releaseStart)
                } else { gain = 0.25 }
            }
            let fade = min(1, max(0, (request.duration - time) / min(0.75, request.duration)))
            return request.volume * Float(gain * fade)
        }
        for pair in zip(ordered, ordered.dropFirst()) {
            request.parameters.setVolumeRamp(fromStartVolume: volume(at: pair.0), toEndVolume: volume(at: pair.1),
                timeRange: CMTimeRange(start: TimelineTimeMap.time(pair.0), end: TimelineTimeMap.time(pair.1)))
        }
    }
}
