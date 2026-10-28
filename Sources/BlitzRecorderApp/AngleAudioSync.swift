import Accelerate
import AVFoundation
import CoreMedia
import Foundation

/// Places video files shot on other devices (an Osmo Pocket, iPhones) on one timeline by their sound, with no clap
/// and no timecode. Each file's audio becomes an onset curve: how sharply its loudness rises every 10 ms. A word
/// starting is the same event in every microphone even when levels, rooms and codecs differ, so the curves line up
/// where the files do. The whole overlap is searched at once, then measured again near its start, middle and end,
/// which shows drift between the devices' clocks.
enum AngleAudioSync {
    static let onsetRate = 100.0
    /// A match counts when the overlap holds at least this much of the shorter file, so a stray click at the very
    /// edge of two files cannot win.
    private static let minimumOverlapSeconds = 20.0
    private static let checkWindowSeconds = 60.0
    private static let checkSearchSeconds = 1.5
    /// Peaks within this distance of the best one are the same match, not a rival.
    private static let sidelobeGuardSeconds = 1.0

    /// One file's onset curve and how loud its speech is.
    struct Onsets: Equatable {
        let values: [Float]
        /// The loudness of the file's louder moments, in dBFS: the file with the highest level makes the cleanest
        /// program audio.
        let speechLevel: Float

        var duration: Double { Double(values.count) / AngleAudioSync.onsetRate }
    }

    /// An offset measured on about a minute of sound, at a point of the file.
    struct Check: Equatable {
        /// Seconds into the file where the measured minute is centred.
        let time: Double
        let offset: Double
    }

    /// Where a file sits on the reference file's timeline.
    struct Placement: Equatable {
        /// Seconds into the reference where this file's first sample plays. Negative when it started earlier.
        let offset: Double
        /// How much faster the file's clock runs, in seconds per second of the file: 0.001 is 30 against 29.97 fps.
        let drift: Double
        /// 0 to 1: how clearly this alignment stands out from every other one.
        let confidence: Double
        /// The offsets measured near the start, middle and end of the file.
        let checks: [Check]

        /// Speeds this far apart drift by more than a frame a minute: the file needs a speed change, not only an offset.
        static let driftLimit = 0.0003
        static let frameTolerance = 1.0 / 60.0

        /// The match is clear, the clocks agree, and every check sits within a frame of the fitted line.
        var isConfident: Bool {
            confidence >= 0.8 && abs(drift) <= Self.driftLimit && fitError <= Self.frameTolerance
        }

        /// The largest distance, in seconds, between a check and the line through offset and drift.
        var fitError: Double {
            checks.map { abs($0.offset - (offset + drift * $0.time)) }.max() ?? 0
        }
    }

    enum SyncError: LocalizedError {
        case noAudio(URL)
        case unreadable(URL)

        var errorDescription: String? {
            switch self {
            case .noAudio(let url): "\(url.lastPathComponent) has no sound to sync by."
            case .unreadable(let url): "\(url.lastPathComponent) could not be read."
            }
        }
    }

    struct PlaceRequest {
        let reference: Onsets
        let other: Onsets
    }

    // MARK: Reading

    static func onsets(url: URL) async throws -> Onsets {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw SyncError.noAudio(url) }
        let format = try await track.load(.formatDescriptions).first?.audioStreamBasicDescription
        let reader = try AVAssetReader(asset: asset)
        // The file's own sample rate on purpose: AVAssetReader's rate conversion drifts on some files (0.2 % on an
        // Osmo Pocket 4 recording, seconds by the end of a podcast), while decoding at the native rate is exact.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        guard reader.canAdd(output) else { throw SyncError.unreadable(url) }
        reader.add(output)
        guard reader.startReading() else { throw SyncError.unreadable(url) }
        let sampleRate = format?.mSampleRate ?? 48_000
        // A damaged header can report no rate at all; nothing could be measured from it.
        guard sampleRate.isFinite, sampleRate >= onsetRate else { throw SyncError.unreadable(url) }
        var meter = LoudnessMeter(sampleRate: sampleRate)
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            try Task.checkCancellation()
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            meter.add(samples)
        }
        guard reader.status == .completed, !meter.loudness.isEmpty else { throw SyncError.unreadable(url) }
        return onsets(loudness: meter.loudness)
    }

    struct SamplesRequest {
        let samples: [Float]
        let sampleRate: Double
    }

    static func onsets(_ request: SamplesRequest) -> Onsets {
        var meter = LoudnessMeter(sampleRate: request.sampleRate)
        meter.add(request.samples)
        return onsets(loudness: meter.loudness)
    }

    /// Loudness every 10 ms, read as the audio streams in. Steps end on exact sample counts, so rates that are not a
    /// multiple of 100 Hz do not drift.
    private struct LoudnessMeter {
        let sampleRate: Double
        private(set) var loudness: [Float] = []
        private var squares: Float = 0
        private var counted = 0
        private var consumed = 0

        init(sampleRate: Double) {
            self.sampleRate = sampleRate
        }

        mutating func add(_ samples: [Float]) {
            var index = 0
            while index < samples.count {
                let boundary = Int((Double(loudness.count + 1) * sampleRate / AngleAudioSync.onsetRate).rounded())
                let take = min(samples.count - index, boundary - consumed)
                guard take > 0 else { return }
                var sum: Float = 0
                samples.withUnsafeBufferPointer { pointer in
                    vDSP_svesq(pointer.baseAddress! + index, 1, &sum, vDSP_Length(take))
                }
                squares += sum
                counted += take
                consumed += take
                index += take
                if consumed == boundary {
                    loudness.append(sqrt(squares / Float(max(1, counted))))
                    squares = 0
                    counted = 0
                }
            }
        }
    }

    private static func onsets(loudness: [Float]) -> Onsets {
        let steps = loudness.count
        var values = [Float](repeating: 0, count: steps)
        var previous = log1p((loudness.first ?? 0) * 1_000)
        for step in 0..<steps {
            let level = log1p(loudness[step] * 1_000)
            values[step] = max(0, level - previous)
            previous = level
        }
        // Clipping and mic bumps make onsets far taller than any word; capped, they count like one.
        if steps > 0 {
            var ceiling = values.sorted()[min(steps - 1, Int(Double(steps) * 0.995))]
            vDSP_vclip(values, 1, [0], &ceiling, &values, 1, vDSP_Length(steps))
        }
        var mean: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(max(1, steps)))
        values = values.map { $0 - mean }
        let loud = loudness.sorted().suffix(max(1, steps / 10))
        let speech = loud.reduce(0, +) / Float(max(1, loud.count))
        return Onsets(values: values, speechLevel: 20 * log10(max(speech, 1e-6)))
    }

    // MARK: Matching

    private static let voteSegments = 8
    private static let segmentSeconds = 60.0

    /// Where `other` sits on `reference`'s timeline, or nil when the two files share no recognisable sound.
    /// Up to eight minutes spread through `other` each vote for every alignment, scored against their own spread,
    /// so one loud moment (a clipped laugh, a bumped mic) cannot outvote a whole conversation.
    static func place(_ request: PlaceRequest) -> Placement? {
        let a = request.reference.values, b = request.other.values
        let minimumOverlap = Int(min(minimumOverlapSeconds * onsetRate, Double(min(a.count, b.count)) * 0.25))
        guard minimumOverlap > 0 else { return nil }
        let segment = min(Int(segmentSeconds * onsetRate), max(minimumOverlap, b.count / 3))
        guard segment > 0, a.count >= segment else { return nil }
        let count = max(1, min(voteSegments, b.count / segment))
        let starts = (0..<count).map { count == 1 ? 0 : (b.count - segment) * $0 / (count - 1) }
        // votes[lag + b.count]: the file starting `lag` onset steps into the reference.
        var votes = [Float](repeating: 0, count: a.count + b.count + 1)
        let reference = Spectrum(values: a, size: transformSize(a.count + segment))
        for start in starts {
            let correlation = reference.correlation(with: Array(b[start..<(start + segment)]))
            let positions = 0...(a.count - segment)
            let scores = positions.map { correlation[$0] }
            var mean: Float = 0, deviation: Float = 0
            vDSP_normalize(scores, 1, nil, 1, &mean, &deviation, vDSP_Length(scores.count))
            guard deviation > 0 else { continue }
            for position in positions {
                votes[position - start + b.count] += (scores[position] - mean) / deviation
            }
        }
        let lags = (-(b.count - minimumOverlap))...(a.count - minimumOverlap)
        let vote = { (lag: Int) -> Float in
            let index = lag + b.count
            return votes.indices.contains(index) ? votes[index] : 0
        }
        var best = (lag: 0, value: -Float.greatestFiniteMagnitude)
        for lag in lags where vote(lag) > best.value { best = (lag, vote(lag)) }
        guard best.value > 0 else { return nil }
        let guardLags = Int(sidelobeGuardSeconds * onsetRate)
        var rival: Float = 0
        for lag in lags where abs(lag - best.lag) > guardLags { rival = max(rival, vote(lag)) }
        let coarse = (Double(best.lag) + parabolicPeak(.init(
            before: vote(best.lag - 1), peak: best.value, after: vote(best.lag + 1)
        ))) / onsetRate
        let checks = checkOffsets(.init(reference: a, other: b, offset: coarse))
        let fit = line(through: checks)
        // A clear match stands well above every other alignment; twice the best rival is already unmistakable.
        let ratio = Double(best.value / max(rival, 1e-6))
        return Placement(offset: fit?.offset ?? coarse, drift: fit?.drift ?? 0,
                         confidence: min(1, max(0, (ratio - 1) / 1.25)), checks: checks)
    }

    private static func transformSize(_ minimum: Int) -> Int {
        var size = 16
        while size < minimum { size <<= 1 }
        return size
    }

    /// The reference's spectrum, kept to correlate several minutes of another file against it.
    private struct Spectrum {
        let size: Int
        let real: [Float]
        let imaginary: [Float]
        let forward: vDSP.DiscreteFourierTransform<Float>?
        let inverse: vDSP.DiscreteFourierTransform<Float>?

        init(values: [Float], size: Int) {
            self.size = size
            forward = try? vDSP.DiscreteFourierTransform(count: size, direction: .forward,
                                                          transformType: .complexComplex, ofType: Float.self)
            inverse = try? vDSP.DiscreteFourierTransform(count: size, direction: .inverse,
                                                          transformType: .complexComplex, ofType: Float.self)
            (real, imaginary) = Self.transform(.init(values: values, size: size, using: forward))
        }

        private struct TransformRequest {
            let values: [Float]
            let size: Int
            let using: vDSP.DiscreteFourierTransform<Float>?
        }

        private static func transform(_ request: TransformRequest) -> ([Float], [Float]) {
            let zeros = [Float](repeating: 0, count: request.size)
            guard let dft = request.using else { return (zeros, zeros) }
            var padded = Array(request.values.prefix(request.size))
            padded.append(contentsOf: repeatElement(0, count: request.size - padded.count))
            var real = zeros, imaginary = zeros
            dft.transform(inputReal: padded, inputImaginary: zeros, outputReal: &real, outputImaginary: &imaginary)
            return (real, imaginary)
        }

        /// result[j] = Σ reference[j + i] × piece[i], for j from 0.
        func correlation(with piece: [Float]) -> [Float] {
            let (pr, pi) = Self.transform(.init(values: piece, size: size, using: forward))
            var productReal = [Float](repeating: 0, count: size), productImaginary = productReal
            for index in 0..<size {
                productReal[index] = real[index] * pr[index] + imaginary[index] * pi[index]
                productImaginary[index] = imaginary[index] * pr[index] - real[index] * pi[index]
            }
            guard let inverse else { return productReal.map { _ in 0 } }
            var outReal = productReal, outImaginary = productImaginary
            inverse.transform(inputReal: productReal, inputImaginary: productImaginary,
                              outputReal: &outReal, outputImaginary: &outImaginary)
            let scale = 1 / Float(size)
            return outReal.map { $0 * scale }
        }
    }

    private struct ParabolaRequest {
        let before: Float
        let peak: Float
        let after: Float
    }

    /// The fraction of a step the true peak sits from the sampled one, from the two neighbours.
    private static func parabolicPeak(_ request: ParabolaRequest) -> Double {
        let curvature = request.before - 2 * request.peak + request.after
        guard curvature < 0 else { return 0 }
        return Double(max(-0.5, min(0.5, 0.5 * (request.before - request.after) / curvature)))
    }

    private struct CheckRequest {
        let reference: [Float]
        let other: [Float]
        let offset: Double
    }

    /// The offset measured again on a minute of sound near the start, middle and end of the overlap.
    private static func checkOffsets(_ request: CheckRequest) -> [Check] {
        let a = request.reference, b = request.other
        let lag = Int((request.offset * onsetRate).rounded())
        let overlapStart = max(0, -lag), overlapEnd = min(b.count, a.count - lag)
        let overlap = overlapEnd - overlapStart
        guard overlap > 0 else { return [] }
        let window = min(Int(checkWindowSeconds * onsetRate), overlap / 3)
        let search = Int(checkSearchSeconds * onsetRate)
        guard window > search else { return [] }
        return [0.1, 0.5, 0.9].compactMap { position in
            let start = overlapStart + Int(Double(overlap - window) * position)
            var best = (lag: lag, value: -Float.greatestFiniteMagnitude)
            var values: [Int: Float] = [:]
            for candidate in (lag - search)...(lag + search) {
                let referenceStart = start + candidate
                guard referenceStart >= 0, referenceStart + window <= a.count else { continue }
                var dot: Float = 0
                a.withUnsafeBufferPointer { ap in
                    b.withUnsafeBufferPointer { bp in
                        vDSP_dotpr(ap.baseAddress! + referenceStart, 1, bp.baseAddress! + start, 1, &dot, vDSP_Length(window))
                    }
                }
                values[candidate] = dot
                if dot > best.value { best = (candidate, dot) }
            }
            guard best.value > 0 else { return nil }
            let refined = Double(best.lag) + parabolicPeak(.init(
                before: values[best.lag - 1] ?? best.value, peak: best.value, after: values[best.lag + 1] ?? best.value
            ))
            return Check(time: (Double(start) + Double(window) / 2) / onsetRate, offset: refined / onsetRate)
        }
    }

    /// The least-squares line offset + drift × time through the checks; nil with fewer than two.
    private static func line(through checks: [Check]) -> (offset: Double, drift: Double)? {
        guard checks.count >= 2 else { return checks.first.map { ($0.offset, 0) } }
        let meanTime = checks.map(\.time).reduce(0, +) / Double(checks.count)
        let meanOffset = checks.map(\.offset).reduce(0, +) / Double(checks.count)
        let spread = checks.map { ($0.time - meanTime) * ($0.time - meanTime) }.reduce(0, +)
        guard spread > 0 else { return (meanOffset, 0) }
        let drift = checks.map { ($0.time - meanTime) * ($0.offset - meanOffset) }.reduce(0, +) / spread
        return (meanOffset - drift * meanTime, drift)
    }
}
