import AVFoundation

enum EditorAudioActivity {
    enum State: Equatable {
        case loading
        case ready([EditorTimeRange])
        case failed(String)

        var ranges: [EditorTimeRange] {
            if case .ready(let ranges) = self { return ranges }
            return []
        }
    }

    static func load(_ asset: EditorAsset) async throws -> [EditorTimeRange] {
        let duration = try await AVURLAsset(url: asset.url).load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw SilenceDetectionError.noAudio }
        let windows = try await SilenceDetection.cachedWindows(.init(audioURL: asset.url, takeDuration: duration,
            sourceOffset: 0, minimumSilence: 0.1, thresholdDB: -60, previousCuts: []))
        try Task.checkCancellation()
        guard !windows.isEmpty else { throw SilenceDetectionError.noAudio }
        return ranges(.init(windows: windows, duration: duration))
    }

    struct Request {
        let windows: [SilenceWindow]
        let duration: Double
    }

    static func ranges(_ request: Request) -> [EditorTimeRange] {
        var result: [EditorTimeRange] = []
        for window in request.windows where window.decibels.isFinite && window.decibels > -60 {
            let start = max(0, window.start - 0.03)
            let end = min(request.duration, window.end + 0.03)
            guard end > start else { continue }
            if let last = result.last, start - last.end <= 0.3 {
                result[result.count - 1] = .init(start: last.start, end: max(last.end, end))
            } else {
                result.append(.init(start: start, end: end))
            }
        }
        return result
    }
}
