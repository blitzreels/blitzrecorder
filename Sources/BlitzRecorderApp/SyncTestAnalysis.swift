import AVFoundation
import Foundation

/// Finds the sync test's claps in a take: white flashes in a picture and 1 kHz beeps in a sound, then measures
/// each track against the claps the test made, so every track's offset, drift and jumps can be compared.
enum SyncTestAnalysis {
    static let toneFrequency = 1_000.0
    /// Gaps between claps; uneven so a track that is seconds off cannot match the wrong clap.
    static let clapIntervals: [Double] = [1.7, 2.3, 1.9, 2.1, 2.5, 1.5]

    struct Sample: Equatable {
        let seconds: Double
        /// Mean brightness, 0 to 1.
        let value: Double
    }

    /// The first frame of each flash. Flashes are short, so the picture is dark most of the time: the median is the
    /// dark level and a high percentile the flash.
    static func flashOnsets(_ frames: [Sample]) -> [Double] {
        guard frames.count > 20 else { return [] }
        let sorted = frames.map(\.value).sorted()
        let dark = sorted[sorted.count / 2]
        let lit = sorted[min(sorted.count - 1, sorted.count * 99 / 100)]
        guard lit - dark > 0.12 else { return [] }
        let threshold = (dark + lit) / 2
        var onsets: [Double] = []
        var wasLit = false
        for frame in frames {
            let isLit = frame.value > threshold
            if isLit, !wasLit { onsets.append(frame.seconds) }
            wasLit = isLit
        }
        return onsets
    }

    struct ToneRequest {
        let samples: [Float]
        let sampleRate: Double
    }

    /// Where each beep starts, from a Goertzel filter at the tone frequency over 5 ms windows every 2.5 ms. A window
    /// counts when most of its energy is the tone, so a voice or music around it does not.
    static func toneOnsets(_ request: ToneRequest) -> [Double] {
        let window = max(32, Int(request.sampleRate * 0.005))
        let hop = window / 2
        guard request.samples.count > window * 4 else { return [] }
        let coefficient = Float(2 * cos(2 * Double.pi * toneFrequency / request.sampleRate))
        var amplitudes: [Float] = []
        var purities: [Float] = []
        var start = 0
        request.samples.withUnsafeBufferPointer { samples in
            while start + window <= samples.count {
                var previous: Float = 0, beforePrevious: Float = 0, energy: Float = 0
                for index in start..<(start + window) {
                    let value = samples[index]
                    let current = value + coefficient * previous - beforePrevious
                    beforePrevious = previous
                    previous = current
                    energy += value * value
                }
                let power = max(0, previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
                amplitudes.append(2 * power.squareRoot() / Float(window))
                purities.append(energy > 0 ? min(1, 2 * power / (Float(window) * energy)) : 0)
                start += hop
            }
        }
        let floor = amplitudes.sorted()[amplitudes.count / 2]
        let minimum = max(floor * 6, 0.003)
        let hopSeconds = Double(hop) / request.sampleRate
        let quietHops = Int(0.3 / hopSeconds)
        var onsets: [Double] = []
        var lastToneHop = -quietHops - 1
        for index in amplitudes.indices where amplitudes[index] > minimum && purities[index] > 0.6 {
            if index - lastToneHop > quietHops {
                onsets.append(Double(index * hop + window / 2) / request.sampleRate)
            }
            lastToneHop = index
        }
        return onsets
    }

    struct MatchRequest {
        /// When the test clapped, on the take timeline.
        let claps: [Double]
        /// When the track shows a clap, on the take timeline.
        let onsets: [Double]
    }

    struct TrackTiming: Equatable {
        /// Per clap, how late the track shows it; nil when the track did not.
        let offsets: [Double?]

        var matched: [Double] { offsets.compactMap { $0 } }
    }

    /// Pairs claps with the track's onsets by the most consistent path through the whole test: staying at one
    /// offset is cheap, a jump costs more than a missing clap, and only a jump that later claps agree with is worth
    /// it. So a track that jumps by seconds mid-take, even by about one gap between claps, shows one step at the
    /// right clap instead of pairing claps with their neighbours.
    static func match(_ request: MatchRequest) -> TrackTiming? {
        struct State {
            let value: Double?
            let carried: Double?
            let cost: Double
            let back: Int
        }
        var layers: [[State]] = []
        for clap in request.claps {
            let candidates = request.onsets.map { $0 - clap }.filter { abs($0) <= searchSeconds }
            let previous = layers.last ?? []
            let values: [Double?] = candidates.map(Optional.some) + [nil]
            layers.append(values.map { value in
                guard !previous.isEmpty else {
                    return State(value: value, carried: value, cost: value == nil ? missCost : 0, back: -1)
                }
                var best = State(value: value, carried: value, cost: .infinity, back: -1)
                for (index, state) in previous.enumerated() {
                    let cost = state.cost + transitionCost(from: state.carried, to: value)
                    if cost < best.cost {
                        best = State(value: value, carried: value ?? state.carried, cost: cost, back: index)
                    }
                }
                return best
            })
        }
        guard var index = layers.last?.indices.min(by: { layers.last![$0].cost < layers.last![$1].cost }) else {
            return nil
        }
        var offsets: [Double?] = Array(repeating: nil, count: layers.count)
        for layer in layers.indices.reversed() {
            let state = layers[layer][index]
            offsets[layer] = state.value
            index = state.back
        }
        let timing = TrackTiming(offsets: offsets)
        return timing.matched.count >= min(request.claps.count, max(3, request.claps.count / 4)) ? timing : nil
    }

    private static let searchSeconds = 3.0
    private static let missCost = 0.4
    private static let steadySeconds = 0.05

    private static func transitionCost(from carried: Double?, to value: Double?) -> Double {
        guard let value else { return missCost }
        guard let carried else { return 0 }
        let change = abs(value - carried)
        return change <= steadySeconds ? change * 2 : 1 + change * 0.05
    }

    struct Comparison: Equatable {
        let matched: Int
        let claps: Int
        /// Median seconds the track is behind the reference; negative when ahead.
        let offset: Double
        /// How much the offset changed from the first third of the test to the last.
        let drift: Double
        /// Largest change between two claps in a row.
        let largestStep: Double

        static let toleratedOffset = 0.045
        static let toleratedDrift = 0.02
        static let toleratedStep = 0.04

        var isSteady: Bool { abs(drift) <= Self.toleratedDrift && largestStep <= Self.toleratedStep }

        var isInSync: Bool { abs(offset) <= Self.toleratedOffset && isSteady && matched * 2 >= claps }
    }

    struct CompareRequest {
        let track: TrackTiming
        let reference: TrackTiming
    }

    static func compare(_ request: CompareRequest) -> Comparison? {
        let differences = zip(request.track.offsets, request.reference.offsets).compactMap { track, reference in
            track.flatMap { value in reference.map { value - $0 } }
        }
        guard differences.count >= 3 else { return nil }
        let third = max(1, differences.count / 3)
        let steps = zip(differences, differences.dropFirst()).map { abs($1 - $0) }
        return Comparison(
            matched: differences.count,
            claps: request.track.offsets.count,
            offset: median(differences),
            drift: median(Array(differences.suffix(third))) - median(Array(differences.prefix(third))),
            largestStep: steps.max() ?? 0
        )
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
    }
}

/// Reads a take's tracks for the sync test: brightness per video frame, sound as one mono channel.
enum SyncTestMedia {
    static let sampleRate = 48_000.0

    static func brightness(_ url: URL) async throws -> [SyncTestAnalysis.Sample] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RecorderError.writerNotReady }
        var samples: [SyncTestAnalysis.Sample] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            samples.append(.init(seconds: time, value: meanLuma(pixels)))
        }
        return samples
    }

    private static func meanLuma(_ pixels: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var total = 0, count = 0
        for row in Swift.stride(from: 0, to: height, by: 8) {
            for column in Swift.stride(from: 0, to: width, by: 8) {
                total += Int(bytes[row * stride + column])
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) / 255 : 0
    }

    static func sound(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RecorderError.writerNotReady }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            samples.append(contentsOf: chunk)
        }
        return samples
    }
}
