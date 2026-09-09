import AVFoundation

struct SilenceDetectionRequest: Sendable {
    let audioURL: URL
    let takeDuration: Double
    let sourceOffset: Double
    let minimumSilence: Double
    let thresholdDB: Double
    let previousCuts: [TimelineCut]
    var paddingBefore: Double = 0.18
    var paddingAfter: Double = 0.18
    var minimumAudio: Double = 0
}

struct SilenceWindow: Sendable {
    let start: Double
    let end: Double
    let decibels: Double
}

enum SilenceDetection {
    static func detect(_ request: SilenceDetectionRequest) async throws -> [TimelineCut] {
        cuts(.init(windows: try await windows(request), configuration: request))
    }

    static func windows(_ request: SilenceDetectionRequest) async throws -> [SilenceWindow] {
        let asset = AVURLAsset(url: request.audioURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SilenceDetectionError.noAudio
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? SilenceDetectionError.noAudio }
        defer { reader.cancelReading() }
        var windows: [SilenceWindow] = []
        var sum = 0.0
        var count = 0
        var windowStart = 0.0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(buffer)
            var values = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let copied = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            guard copied == kCMBlockBufferNoErr else { throw SilenceDetectionError.noAudio }
            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            for (index, value) in values.enumerated() {
                let time = sampleTime + Double(index) / 16_000 + request.sourceOffset
                if count == 0 { windowStart = time }
                sum += Double(value) * Double(value)
                count += 1
                if count == 320 {
                    windows.append(.init(start: windowStart, end: time + 1 / 16_000,
                                         decibels: 10 * log10(max(1e-12, sum / Double(count)))))
                    sum = 0
                    count = 0
                }
            }
        }
        if reader.status == .failed { throw reader.error ?? SilenceDetectionError.noAudio }
        if count > 0 { windows.append(.init(start: windowStart, end: windowStart + Double(count) / 16_000, decibels: 10 * log10(max(1e-12, sum / Double(count))))) }
        return windows
    }

    static func combinedWindows(_ tracks: [[SilenceWindow]]) -> [SilenceWindow] {
        guard tracks.count > 1 else { return tracks.first ?? [] }
        var levels: [Int: Double] = [:]
        for track in tracks {
            for window in track {
                let first = Int(floor(window.start * 50))
                let last = max(first, Int(ceil(window.end * 50 - 0.00001)) - 1)
                for index in first...last { levels[index] = max(levels[index] ?? -120, window.decibels) }
            }
        }
        return levels.keys.sorted().map { index in
            .init(start: Double(index) / 50, end: Double(index + 1) / 50, decibels: levels[index]!)
        }
    }

    static func suggestedThreshold(_ windows: [SilenceWindow]) -> Double {
        let levels = windows.map(\.decibels).filter { $0.isFinite }.sorted()
        guard !levels.isEmpty else { return -42 }
        let noise = levels[Int(Double(levels.count - 1) * 0.15)]
        let speech = levels[Int(Double(levels.count - 1) * 0.85)]
        return min(-25, max(-60, min(noise + 8, speech - 12)))
    }

    struct CutRequest {
        let windows: [SilenceWindow]
        let configuration: SilenceDetectionRequest
    }

    static func cuts(_ request: CutRequest) -> [TimelineCut] {
        let config = request.configuration
        var ranges: [(Double, Double)] = []
        var start: Double?
        var end = 0.0
        for window in request.windows {
            let threshold = start == nil ? config.thresholdDB : config.thresholdDB + 3
            if window.decibels < threshold {
                if start == nil { start = window.start }
                end = window.end
            } else if let from = start {
                ranges.append((from, end))
                start = nil
            }
        }
        if let start { ranges.append((start, end)) }
        if config.minimumAudio > 0, ranges.count > 1 {
            var merged: [(Double, Double)] = []
            for range in ranges {
                if let last = merged.last, range.0 - last.1 < config.minimumAudio {
                    merged[merged.count - 1] = (last.0, range.1)
                } else { merged.append(range) }
            }
            ranges = merged
        }
        let detected = ranges.compactMap { range -> TimelineCut? in
            let from = max(0, range.0 + config.paddingAfter)
            let to = min(config.takeDuration, range.1 - config.paddingBefore)
            guard range.1 - range.0 >= max(0.1, config.minimumSilence), to - from > 0.02 else { return nil }
            let wasRestored = config.previousCuts.contains {
                $0.source == .automatic && !$0.isEnabled && $0.start < to && $0.end > from
            }
            return TimelineCut(start: from, end: to, kind: .silence, source: .automatic, isEnabled: !wasRestored)
        }
        return config.previousCuts.filter { $0.source == .user } + detected
    }
}

enum SilenceDetectionError: LocalizedError {
    case noAudio
    var errorDescription: String? { "No readable audio was found. Select a take with a microphone or audio track." }
}
