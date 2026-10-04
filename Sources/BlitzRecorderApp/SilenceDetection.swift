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
    var speechRanges: [RecordingTranscript.SpeechRange] = []
    var onProgress: (@Sendable (Double) -> Void)? = nil
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
        let totalSeconds = (try? await asset.load(.duration).seconds).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        guard reader.startReading() else { throw reader.error ?? SilenceDetectionError.noAudio }
        defer { reader.cancelReading() }
        var reported = 0.0
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
            if let totalSeconds, let onProgress = request.onProgress {
                let fraction = min(1, max(0, (sampleTime + Double(values.count) / 16_000) / totalSeconds))
                if fraction - reported >= 0.01 {
                    reported = fraction
                    onProgress(fraction)
                }
            }
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
            ranges = mergingQuietInterruptions(.init(
                ranges: ranges, windows: request.windows, configuration: config
            ))
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

    private struct MergeRequest {
        let ranges: [(Double, Double)]
        let windows: [SilenceWindow]
        let configuration: SilenceDetectionRequest
    }

    private static func mergingQuietInterruptions(_ request: MergeRequest) -> [(Double, Double)] {
        let config = request.configuration
        let speech = config.speechRanges.filter {
            $0.startTime.isFinite && $0.endTime.isFinite && $0.endTime > $0.startTime
        }.sorted { $0.startTime < $1.startTime }
        let kept = config.previousCuts.filter { !$0.isEnabled }.map { ($0.start, $0.end) }
            + config.overrides.filter { $0.classification == .sound }.map { ($0.start, $0.end) }
        let quietLimit = min(-30, config.thresholdDB + 12)
        let tick = 1.0 / 600
        var merged: [(Double, Double)] = []
        var speechIndex = 0
        var windowIndex = 0
        for range in request.ranges {
            guard let last = merged.last, range.0 - last.1 <= config.minimumAudio + tick else {
                merged.append(range)
                continue
            }
            while speechIndex < speech.count, speech[speechIndex].endTime <= last.1 { speechIndex += 1 }
            let containsSpeech = speechIndex < speech.count && speech[speechIndex].startTime < range.0
            let containsKeptRange = kept.contains { $0.0 < range.1 && $0.1 > last.0 }
            while windowIndex < request.windows.count, request.windows[windowIndex].end <= last.1 { windowIndex += 1 }
            var index = windowIndex
            var coveredUntil = last.1
            var isQuiet = true
            while index < request.windows.count, request.windows[index].start < range.0 {
                let window = request.windows[index]
                if !window.decibels.isFinite || window.decibels > quietLimit || window.start > coveredUntil + tick {
                    isQuiet = false
                    break
                }
                coveredUntil = max(coveredUntil, window.end)
                index += 1
            }
            if !containsSpeech, !containsKeptRange, isQuiet, coveredUntil >= range.0 - tick {
                merged[merged.count - 1] = (last.0, range.1)
            } else {
                merged.append(range)
            }
        }
        return merged
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

actor SilenceWindowCache {
    struct Configuration {
        let directory: URL
        let byteLimit: Int
    }

    struct Key {
        let file: MediaFileFingerprint
        let sourceOffset: Double
    }

    struct SaveRequest {
        let key: Key
        let windows: [SilenceWindow]
    }

    static let shared = SilenceWindowCache(.init(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlitzRecorder/SilenceWindows-v1", isDirectory: true),
        byteLimit: 128 * 1_024 * 1_024
    ))

    private static let maximumWindows = 2_000_000
    private let configuration: Configuration
    private let header = Data("BRSW0001".utf8)

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func load(_ key: Key) -> [SilenceWindow]? {
        let url = fileURL(key)
        guard !Task.isCancelled,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count >= 16, data.prefix(8) == header else { return nil }
        let count = data.withUnsafeBytes { Int(UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))) }
        let stride = 3 * MemoryLayout<Double>.size
        guard count > 0, count <= Self.maximumWindows, data.count == 16 + count * stride else { return nil }
        let windows = data.withUnsafeBytes { bytes in
            (0..<count).map { index in
                let offset = 16 + index * stride
                return SilenceWindow(
                    start: bytes.loadUnaligned(fromByteOffset: offset, as: Double.self),
                    end: bytes.loadUnaligned(fromByteOffset: offset + 8, as: Double.self),
                    decibels: bytes.loadUnaligned(fromByteOffset: offset + 16, as: Double.self)
                )
            }
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return windows
    }

    func save(_ request: SaveRequest) {
        guard !Task.isCancelled, !request.windows.isEmpty, request.windows.count <= Self.maximumWindows else { return }
        var data = header
        data.reserveCapacity(16 + request.windows.count * 24)
        var count = UInt64(request.windows.count).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for window in request.windows {
            for value in [window.start, window.end, window.decibels] {
                withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
            }
        }
        do {
            try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(request.key), options: .atomic)
            prune()
        } catch {}
    }

    private func fileURL(_ key: Key) -> URL {
        configuration.directory.appendingPathComponent("\(key.file.cacheKey)-\(key.sourceOffset.bitPattern).brsw")
    }

    private func prune() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: configuration.directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        ) else { return }
        let entries = files.filter { $0.pathExtension == "brsw" }.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > configuration.byteLimit {
            if (try? FileManager.default.removeItem(at: entry.0)) != nil { total -= entry.1 }
        }
    }
}

extension SilenceDetection {
    static func cachedWindows(_ request: SilenceDetectionRequest) async throws -> [SilenceWindow] {
        guard let file = MediaFileFingerprint(url: request.audioURL) else { return try await windows(request) }
        let key = SilenceWindowCache.Key(file: file, sourceOffset: request.sourceOffset)
        if let cached = await SilenceWindowCache.shared.load(key) { return cached }
        let computed = try await windows(request)
        await SilenceWindowCache.shared.save(.init(key: key, windows: computed))
        return computed
    }
}
