import Accelerate
import AVFoundation
import Foundation

/// Studio voice: rumble cut, clearer tone, softer "s" sounds, a steady level, quieter gaps, and a fixed loudness
/// (-16 LUFS, peaks under -1.5 dBFS), so every recording plays back as loud as the last.
enum VoiceEnhancer {
    static let targetLoudness = -16.0
    static let ceiling: Float = 0.84
    static let blockSize = 64
    private static let chunkSize: AVAudioFrameCount = 4096
    static let limiterLookaheadBlocks = 4

    struct Request {
        let source: URL
        let destination: URL
        let progress: (Double) -> Void
    }

    static func process(_ request: Request) throws {
        let input = try AVAudioFile(forReading: request.source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        guard format.channelCount > 0, input.length > 0 else {
            throw RecorderError.mediaWriteFailed("The microphone source has no readable samples.")
        }
        let shapedURL = request.destination.deletingLastPathComponent()
            .appendingPathComponent("shaped-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: shapedURL) }

        let inputMeter = try LoudnessMeter(format: format)
        try forEachChunk(.init(file: input, progress: { request.progress(0.15 * $0) }, body: inputMeter.add))
        let preGain = inputMeter.integrated.map { gain(dB: min(30, max(-20, -20 - $0))) } ?? 1

        let shaper = try VoiceShaper(.init(format: format, preGain: preGain))
        let shapedMeter = try LoudnessMeter(format: format)
        let shaped = try AVAudioFile(forWriting: shapedURL, settings: pcmSettings(format),
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        input.framePosition = 0
        try forEachChunk(.init(file: input, progress: { request.progress(0.15 + 0.45 * $0) }, body: { buffer in
            shaper.process(buffer)
            shapedMeter.add(buffer)
            try shaped.write(from: buffer)
        }))
        shaped.close()

        let heard = shapedMeter.integrated.map { $0 + (format.channelCount == 1 ? 3.01 : 0) }
        let makeup = heard.map { gain(dB: min(20, max(-20, targetLoudness - $0))) } ?? 1
        let reader = try AVAudioFile(forReading: shapedURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        let limiter = PeakLimiter(.init(length: Int(reader.length), makeup: makeup, sampleRate: format.sampleRate))
        try forEachChunk(.init(file: reader, progress: { request.progress(0.6 + 0.15 * $0) }, body: limiter.measure))
        limiter.prepare()

        let output = try AVAudioFile(forWriting: request.destination, settings: pcmSettings(format),
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        reader.framePosition = 0
        try forEachChunk(.init(file: reader, progress: { request.progress(0.75 + 0.25 * $0) }, body: { buffer in
            limiter.apply(buffer)
            try output.write(from: buffer)
        }))
        output.close()
    }

    static func gain(dB: Double) -> Float {
        Float(pow(10, dB / 20))
    }

    static func decibels(_ meanSquare: Float) -> Double {
        10 * log10(Double(max(meanSquare, 1e-12)))
    }

    static func smoothing(_ step: SmoothingStep) -> Float {
        Float(1 - exp(-Double(step.frames) / (step.seconds * step.sampleRate)))
    }

    struct SmoothingStep {
        let seconds: Double
        let frames: Int
        let sampleRate: Double
    }

    private static func pcmSettings(_ format: AVAudioFormat) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
         AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true]
    }

    private struct Pass {
        let file: AVAudioFile
        let progress: (Double) -> Void
        let body: (AVAudioPCMBuffer) throws -> Void
    }

    private static func forEachChunk(_ pass: Pass) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pass.file.processingFormat, frameCapacity: chunkSize) else {
            throw RecorderError.mediaWriteFailed("Cannot allocate studio voice buffers.")
        }
        let length = max(1, pass.file.length)
        var chunks = 0
        while pass.file.framePosition < pass.file.length {
            try Task.checkCancellation()
            try pass.file.read(into: buffer, frameCount: chunkSize)
            guard buffer.frameLength > 0 else { break }
            try pass.body(buffer)
            chunks += 1
            if chunks % 100 == 0 { pass.progress(Double(pass.file.framePosition) / Double(length)) }
        }
        pass.progress(1)
    }
}

/// A cascade of biquad sections for one channel; coefficients are [b0, b1, b2, a1, a2] per section.
private final class BiquadChain {
    private let setup: vDSP_biquad_Setup
    private var delay: [Float]

    init(sections: [[Double]]) throws {
        guard let setup = vDSP_biquad_CreateSetup(sections.flatMap { $0 }, vDSP_Length(sections.count)) else {
            throw RecorderError.mediaWriteFailed("Studio voice is unavailable on this Mac.")
        }
        self.setup = setup
        delay = [Float](repeating: 0, count: 2 * sections.count + 2)
    }

    deinit { vDSP_biquad_DestroySetup(setup) }

    struct Run {
        let input: UnsafePointer<Float>
        let output: UnsafeMutablePointer<Float>
        let count: Int
    }

    func run(_ run: Run) {
        vDSP_biquad(setup, &delay, run.input, 1, run.output, 1, vDSP_Length(run.count))
    }
}

/// Audio EQ Cookbook (RBJ) sections.
private struct BiquadBand {
    enum Kind {
        case highPass(q: Double)
        case peak(gainDB: Double, q: Double)
        case highShelf(gainDB: Double)
    }

    let kind: Kind
    let frequency: Double
    let sampleRate: Double

    var isPlayable: Bool { frequency < sampleRate * 0.45 }

    var coefficients: [Double] {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let sinW = sin(w0)
        let b: [Double]
        let a: [Double]
        switch kind {
        case .highPass(let q):
            let alpha = sinW / (2 * q)
            b = [(1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2]
            a = [1 + alpha, -2 * cosW, 1 - alpha]
        case .peak(let gainDB, let q):
            let amplitude = pow(10, gainDB / 40)
            let alpha = sinW / (2 * q)
            b = [1 + alpha * amplitude, -2 * cosW, 1 - alpha * amplitude]
            a = [1 + alpha / amplitude, -2 * cosW, 1 - alpha / amplitude]
        case .highShelf(let gainDB):
            let amplitude = pow(10, gainDB / 40)
            let alpha = sinW / 2 * sqrt(2)
            let root = 2 * sqrt(amplitude) * alpha
            b = [amplitude * ((amplitude + 1) + (amplitude - 1) * cosW + root),
                 -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosW),
                 amplitude * ((amplitude + 1) + (amplitude - 1) * cosW - root)]
            a = [(amplitude + 1) - (amplitude - 1) * cosW + root,
                 2 * ((amplitude - 1) - (amplitude + 1) * cosW),
                 (amplitude + 1) - (amplitude - 1) * cosW - root]
        }
        return [b[0] / a[0], b[1] / a[0], b[2] / a[0], a[1] / a[0], a[2] / a[0]]
    }
}

/// Integrated loudness per ITU-R BS.1770-4: K-weighting, 400 ms blocks every 100 ms, absolute and relative gates.
final class LoudnessMeter {
    private let filters: [BiquadChain]
    private let subBlockFrames: Int
    private var subBlockFilled = 0
    private var channelSums: [Float]
    private var powers: [Double] = []
    private var scratch: [Float] = []

    init(format: AVAudioFormat) throws {
        let rate = format.sampleRate
        let shelfK = tan(Double.pi * 1681.974450955533 / rate)
        let shelfQ = 0.7071752369554196
        let vh = pow(10, 3.999843853973347 / 20)
        let vb = pow(vh, 0.4996667741545416)
        let shelfA0 = 1 + shelfK / shelfQ + shelfK * shelfK
        let shelf = [(vh + vb * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
                     2 * (shelfK * shelfK - vh) / shelfA0,
                     (vh - vb * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
                     2 * (shelfK * shelfK - 1) / shelfA0,
                     (1 - shelfK / shelfQ + shelfK * shelfK) / shelfA0]
        let highK = tan(Double.pi * 38.13547087602444 / rate)
        let highQ = 0.5003270373238773
        let highA0 = 1 + highK / highQ + highK * highK
        let highPass = [1, -2, 1, 2 * (highK * highK - 1) / highA0, (1 - highK / highQ + highK * highK) / highA0]
        let channels = Int(format.channelCount)
        filters = try (0..<channels).map { _ in try BiquadChain(sections: [shelf, highPass]) }
        subBlockFrames = max(1, Int((rate * 0.1).rounded()))
        channelSums = [Float](repeating: 0, count: channels)
    }

    func add(_ buffer: AVAudioPCMBuffer) {
        let count = Int(buffer.frameLength)
        guard count > 0, let data = buffer.floatChannelData, filters.count == channelSums.count else { return }
        if scratch.count < count { scratch = [Float](repeating: 0, count: count) }
        var offset = 0
        while offset < count {
            let length = min(subBlockFrames - subBlockFilled, count - offset)
            for channel in filters.indices {
                var sum: Float = 0
                scratch.withUnsafeMutableBufferPointer { weighted in
                    filters[channel].run(.init(input: data[channel] + offset, output: weighted.baseAddress!, count: length))
                    vDSP_svesq(weighted.baseAddress!, 1, &sum, vDSP_Length(length))
                }
                channelSums[channel] += sum
            }
            subBlockFilled += length
            offset += length
            if subBlockFilled == subBlockFrames {
                powers.append(channelSums.reduce(0) { $0 + Double($1) } / Double(subBlockFrames))
                channelSums = channelSums.map { _ in 0 }
                subBlockFilled = 0
            }
        }
    }

    /// LUFS of the gated speech, nil when nothing rises above the -70 LUFS gate.
    var integrated: Double? {
        guard powers.count >= 4 else { return nil }
        let blocks = (0...(powers.count - 4)).map { (powers[$0] + powers[$0 + 1] + powers[$0 + 2] + powers[$0 + 3]) / 4 }
        let loudness = { (power: Double) in -0.691 + 10 * log10(max(power, 1e-20)) }
        let audible = blocks.filter { loudness($0) > -70 }
        guard !audible.isEmpty else { return nil }
        let relativeGate = loudness(audible.reduce(0, +) / Double(audible.count)) - 10
        let gated = audible.filter { loudness($0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        return loudness(gated.reduce(0, +) / Double(gated.count))
    }
}

/// Tone, de-essing, compression and a gentle expander, working at speech level (-20 LUFS after the pre-gain).
private final class VoiceShaper {
    struct Setup {
        let format: AVAudioFormat
        let preGain: Float
    }

    private let sampleRate: Double
    private let preGain: Float
    private let tone: [BiquadChain]
    private let sibilance: [BiquadChain]
    private var side: [[Float]]
    private var scratch: [Float] = []
    private var deEssGain: Float = 1
    private var levelGain: Float = 1
    private var compressorEnvelope = -100.0
    private var gateEnvelope = -100.0

    init(_ setup: Setup) throws {
        sampleRate = setup.format.sampleRate
        preGain = setup.preGain
        let channels = Int(setup.format.channelCount)
        let rate = sampleRate
        let toneBands = [
            BiquadBand(kind: .highPass(q: 0.5412), frequency: 70, sampleRate: rate),
            BiquadBand(kind: .highPass(q: 1.3066), frequency: 70, sampleRate: rate),
            BiquadBand(kind: .peak(gainDB: -1.5, q: 1), frequency: 250, sampleRate: rate),
            BiquadBand(kind: .peak(gainDB: 2.5, q: 0.9), frequency: 3200, sampleRate: rate),
            BiquadBand(kind: .highShelf(gainDB: 1.5), frequency: 9000, sampleRate: rate),
        ].filter(\.isPlayable).map(\.coefficients)
        let sibilanceBands = rate >= 22050 ? [
            BiquadBand(kind: .highPass(q: 0.5412), frequency: 5500, sampleRate: rate),
            BiquadBand(kind: .highPass(q: 1.3066), frequency: 5500, sampleRate: rate),
        ].map(\.coefficients) : []
        tone = try (0..<channels).map { _ in try BiquadChain(sections: toneBands) }
        sibilance = sibilanceBands.isEmpty ? [] : try (0..<channels).map { _ in try BiquadChain(sections: sibilanceBands) }
        side = Array(repeating: [], count: channels)
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let count = Int(buffer.frameLength)
        guard count > 0, let data = buffer.floatChannelData else { return }
        if scratch.count < count { scratch = [Float](repeating: 0, count: count) }
        for channel in tone.indices {
            var gain = preGain
            vDSP_vsmul(data[channel], 1, &gain, data[channel], 1, vDSP_Length(count))
            scratch.withUnsafeMutableBufferPointer { shaped in
                tone[channel].run(.init(input: data[channel], output: shaped.baseAddress!, count: count))
                data[channel].update(from: shaped.baseAddress!, count: count)
            }
            if !sibilance.isEmpty {
                if side[channel].count < count { side[channel] = [Float](repeating: 0, count: count) }
                side[channel].withUnsafeMutableBufferPointer { band in
                    sibilance[channel].run(.init(input: data[channel], output: band.baseAddress!, count: count))
                }
            }
        }
        var offset = 0
        while offset < count {
            let length = min(VoiceEnhancer.blockSize, count - offset)
            if !sibilance.isEmpty { deEss(.init(data: data, offset: offset, length: length)) }
            level(.init(data: data, offset: offset, length: length))
            offset += length
        }
    }

    private struct Block {
        let data: UnsafePointer<UnsafeMutablePointer<Float>>
        let offset: Int
        let length: Int
    }

    private func meanSquare(_ block: Block) -> Float {
        var total: Float = 0
        for channel in tone.indices {
            var value: Float = 0
            vDSP_measqv(block.data[channel] + block.offset, 1, &value, vDSP_Length(block.length))
            total += value
        }
        return total / Float(tone.count)
    }

    private func deEss(_ block: Block) {
        let full = VoiceEnhancer.decibels(meanSquare(block))
        var sideTotal: Float = 0
        for channel in side.indices {
            var value: Float = 0
            side[channel].withUnsafeBufferPointer { band in
                vDSP_measqv(band.baseAddress! + block.offset, 1, &value, vDSP_Length(block.length))
            }
            sideTotal += value
        }
        let sibilant = VoiceEnhancer.decibels(sideTotal / Float(side.count))
        let excess = sibilant - full + 9
        let target = sibilant > -50 && excess > 0 ? VoiceEnhancer.gain(dB: -min(6, excess * 0.75)) : 1
        let next = target < deEssGain ? target : deEssGain + (target - deEssGain) * VoiceEnhancer.smoothing(
            .init(seconds: 0.04, frames: block.length, sampleRate: sampleRate))
        guard deEssGain < 0.999 || next < 0.999 else {
            deEssGain = next
            return
        }
        for channel in side.indices {
            var start = 1 - deEssGain
            var step = (deEssGain - next) / Float(block.length)
            scratch.withUnsafeMutableBufferPointer { removed in
                side[channel].withUnsafeBufferPointer { band in
                    vDSP_vrampmul(band.baseAddress! + block.offset, 1, &start, &step, removed.baseAddress!, 1,
                                  vDSP_Length(block.length))
                }
                let samples = block.data[channel] + block.offset
                vDSP_vsub(removed.baseAddress!, 1, samples, 1, samples, 1, vDSP_Length(block.length))
            }
        }
        deEssGain = next
    }

    private func level(_ block: Block) {
        let level = VoiceEnhancer.decibels(meanSquare(block))
        let attack = Double(VoiceEnhancer.smoothing(.init(seconds: 0.005, frames: block.length, sampleRate: sampleRate)))
        let release = Double(VoiceEnhancer.smoothing(.init(seconds: 0.12, frames: block.length, sampleRate: sampleRate)))
        compressorEnvelope += (level - compressorEnvelope) * (level > compressorEnvelope ? attack : release)
        gateEnvelope = level > gateEnvelope ? level : gateEnvelope + (level - gateEnvelope) * release
        let next = VoiceEnhancer.gain(dB: Self.compression(compressorEnvelope) + Self.expansion(gateEnvelope))
        var step = (next - levelGain) / Float(block.length)
        for channel in tone.indices {
            var start = levelGain
            let samples = block.data[channel] + block.offset
            vDSP_vrampmul(samples, 1, &start, &step, samples, 1, vDSP_Length(block.length))
        }
        levelGain = next
    }

    /// 2.5:1 above -22 dBFS with an 8 dB soft knee.
    static func compression(_ level: Double) -> Double {
        let threshold = -22.0, ratio = 2.5, knee = 8.0
        let over = level - threshold
        if 2 * over < -knee { return 0 }
        if 2 * abs(over) <= knee { return (1 / ratio - 1) * pow(over + knee / 2, 2) / (2 * knee) }
        return (1 / ratio - 1) * over
    }

    /// Lowers what is left between phrases (30 dB under speech) by up to 12 dB.
    static func expansion(_ level: Double) -> Double {
        max(-12, min(0, level + 50))
    }
}

/// Brings the voice to the loudness target and keeps peaks under the ceiling with a 5 ms lookahead.
private final class PeakLimiter {
    struct Setup {
        let length: Int
        let makeup: Float
        let sampleRate: Double
    }

    private let makeup: Float
    private let sampleRate: Double
    private var allowed: [Float]
    private var gains: [Float] = []
    private var position = 0

    init(_ setup: Setup) {
        makeup = setup.makeup
        sampleRate = setup.sampleRate
        allowed = [Float](repeating: 1, count: setup.length / VoiceEnhancer.blockSize + 1)
    }

    func measure(_ buffer: AVAudioPCMBuffer) {
        forEachBlock(.init(buffer: buffer, body: { [self] run in
            let block = run.block
            var peak: Float = 0
            vDSP_maxmgv(run.samples, 1, &peak, vDSP_Length(block.length))
            let limit = min(1, VoiceEnhancer.ceiling / max(peak * makeup, 1e-9))
            allowed[block.index] = min(allowed[block.index], limit)
        }))
    }

    func prepare() {
        let release = VoiceEnhancer.smoothing(.init(seconds: 0.08, frames: VoiceEnhancer.blockSize, sampleRate: sampleRate))
        gains = allowed.indices.map { index in
            allowed[index...min(allowed.count - 1, index + VoiceEnhancer.limiterLookaheadBlocks)].min() ?? 1
        }
        for index in gains.indices.dropFirst() {
            gains[index] = min(gains[index], gains[index - 1] + (1 - gains[index - 1]) * release)
        }
        position = 0
    }

    func apply(_ buffer: AVAudioPCMBuffer) {
        forEachBlock(.init(buffer: buffer, body: { [self] run in
            let block = run.block
            let samples = run.samples
            let current = gains[block.index]
            let previous = block.index > 0 ? gains[block.index - 1] : current
            var step = (current - previous) * makeup / Float(VoiceEnhancer.blockSize)
            var start = previous * makeup + step * Float(block.start - block.index * VoiceEnhancer.blockSize)
            vDSP_vrampmul(samples, 1, &start, &step, samples, 1, vDSP_Length(block.length))
            var low = -VoiceEnhancer.ceiling
            var high = VoiceEnhancer.ceiling
            vDSP_vclip(samples, 1, &low, &high, samples, 1, vDSP_Length(block.length))
        }))
    }

    private struct Block {
        let index: Int
        let start: Int
        let length: Int
    }

    private struct BlockRun {
        let block: Block
        let samples: UnsafeMutablePointer<Float>
    }

    private struct BlockPass {
        let buffer: AVAudioPCMBuffer
        let body: (BlockRun) -> Void
    }

    private func forEachBlock(_ pass: BlockPass) {
        let buffer = pass.buffer
        let count = Int(buffer.frameLength)
        guard count > 0, let data = buffer.floatChannelData else { return }
        var offset = 0
        while offset < count {
            let start = position + offset
            let index = min(allowed.count - 1, start / VoiceEnhancer.blockSize)
            let length = min((index + 1) * VoiceEnhancer.blockSize - start, count - offset)
            let block = Block(index: index, start: start, length: max(1, length))
            for channel in 0..<Int(buffer.format.channelCount) { pass.body(.init(block: block, samples: data[channel] + offset)) }
            offset += block.length
        }
        position += count
    }
}
