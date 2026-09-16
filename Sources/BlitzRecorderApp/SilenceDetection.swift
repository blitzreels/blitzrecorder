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
    var overrides: [SilenceOverride] = []
}

struct SilenceWindow: Equatable, Sendable {
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
        for window in coveringTimeline(request.windows, duration: config.takeDuration) {
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
            let tick = 1.0 / 600
            let startsAtOrigin = range.0 <= tick
            let endsAtTake = range.1 >= config.takeDuration - tick
            let from = max(0, startsAtOrigin ? range.0 : range.0 + config.paddingAfter)
            let to = min(config.takeDuration, endsAtTake ? range.1 : range.1 - config.paddingBefore)
            guard range.1 - range.0 >= max(0.1, config.minimumSilence), to - from > 0.02 else { return nil }
            let wasRestored = config.previousCuts.contains { cut in
                cut.source == .automatic && !cut.isEnabled && cut.start < to && cut.end > from
                    && !config.overrides.contains { $0.start <= cut.start && $0.end >= cut.end }
            }
            return TimelineCut(start: from, end: to, kind: .silence, source: .automatic, isEnabled: !wasRestored)
        }
        return applyingOverrides(.init(
            cuts: config.previousCuts.filter { $0.source == .user } + detected,
            overrides: config.overrides
        ))
    }

    private static func coveringTimeline(_ windows: [SilenceWindow], duration: Double) -> [SilenceWindow] {
        guard duration.isFinite, duration > 0, !windows.isEmpty else { return windows }
        var result = windows
        if let first = result.first, first.start > 0 {
            result.insert(.init(start: 0, end: first.start, decibels: -120), at: 0)
        }
        if let last = result.last, last.end < duration {
            result.append(.init(start: last.end, end: duration, decibels: -120))
        }
        return result
    }

    struct OverrideRequest {
        let cuts: [TimelineCut]
        let overrides: [SilenceOverride]
    }

    static func applyingOverrides(_ request: OverrideRequest) -> [TimelineCut] {
        guard !request.overrides.isEmpty else { return request.cuts }
        var cuts = request.cuts
        for override in request.overrides {
            guard override.start.isFinite, override.end.isFinite, override.end > override.start else { continue }
            cuts = cuts.flatMap { cut -> [TimelineCut] in
                guard cut.kind == .silence, cut.start < override.end, cut.end > override.start else { return [cut] }
                var pieces: [TimelineCut] = []
                if cut.start < override.start {
                    var before = cut
                    before.end = override.start
                    pieces.append(before)
                }
                if cut.end > override.end {
                    pieces.append(.init(
                        start: override.end, end: cut.end, kind: cut.kind,
                        source: cut.source, isEnabled: cut.isEnabled
                    ))
                }
                return pieces
            }
            cuts.append(.init(
                id: override.id, start: override.start, end: override.end, kind: .silence,
                source: .user, isEnabled: override.classification == .silence
            ))
        }
        return cuts.sorted { $0.start < $1.start }
    }

    struct ClassificationRequest {
        let range: EditorTimeRange
        let classification: SilenceClassification
        let edits: TimelineEdits
        let duration: Double
    }

    static func classifying(_ request: ClassificationRequest) -> TimelineEdits? {
        guard let range = EditorTimeRange.resolve(.init(
            anchor: request.range.start, head: request.range.end, duration: request.duration
        )), range.canCut else { return nil }
        var edits = request.edits
        edits.silenceOverrides = edits.silenceOverrides.flatMap { override -> [SilenceOverride] in
            guard override.start < range.end, override.end > range.start else { return [override] }
            var pieces: [SilenceOverride] = []
            if override.start < range.start {
                var before = override
                before.end = range.start
                pieces.append(before)
            }
            if override.end > range.end {
                pieces.append(.init(
                    id: UUID(), start: range.end, end: override.end, classification: override.classification
                ))
            }
            return pieces
        }
        edits.silenceOverrides.append(.init(
            id: UUID(), start: range.start, end: range.end, classification: request.classification
        ))
        edits.silenceOverrides.sort { $0.start < $1.start }
        if request.classification == .sound {
            var silenceEdits = edits
            silenceEdits.cuts = edits.cuts.filter { $0.kind == .silence }
            if let restored = EditorTimeRange.restoring(.init(
                range: range, edits: silenceEdits, takeDuration: request.duration
            )) {
                edits.cuts = edits.cuts.filter { $0.kind != .silence } + restored.cuts
            }
        }
        if request.edits.silenceRemovalApplied || request.edits.enabledCuts.contains(where: { $0.kind == .silence }) {
            edits.silenceRemovalApplied = true
            edits.cuts = applyingOverrides(.init(cuts: edits.cuts, overrides: edits.silenceOverrides))
            let map = TimelineTimeMap(takeDuration: TimelineTimeMap.time(request.duration), cuts: edits.cuts)
            guard map.outputDuration.seconds >= 0.1 else { return nil }
        }
        return edits
    }
}

enum SilenceDetectionError: LocalizedError {
    case noAudio
    var errorDescription: String? { "No readable audio was found. Select a take with a microphone or audio track." }
}
